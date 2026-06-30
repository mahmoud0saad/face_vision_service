import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../entities/detected_face.dart';
import '../entities/model_paths.dart';
import '../entities/vision_detection_config.dart';
import '../vision_constants.dart';
import 'ear_eye_state_analyzer.dart';
import 'eye_state_analyzer.dart';
import 'eye_state_combiner.dart';
import 'face_aligner.dart';
import 'face_box_geometry.dart';
import 'face_preprocessor.dart';

class OpenCvVisionDatasource {
  OpenCvVisionDatasource({VisionDetectionConfig? detectionConfig})
      : detectionConfig = detectionConfig ?? const VisionDetectionConfig();

  cv.FaceDetectorYN? _detector;
  cv.Net? _ageNet;
  cv.Net? _genderNet;
  bool _loaded = false;

  VisionDetectionConfig detectionConfig;

  final EyeStateAnalyzer _laplacianEyeAnalyzer = EyeStateAnalyzer();
  final EarEyeStateAnalyzer _earEyeAnalyzer = EarEyeStateAnalyzer();
  final EyeStateCombiner _eyeCombiner = EyeStateCombiner();
  final FacePreprocessor _preprocessor = FacePreprocessor();
  final FaceAligner _aligner = FaceAligner();

  /// Releases cached preprocessing resources (LUT/CLAHE).
  void dispose() {
    _preprocessor.dispose();
  }

  Future<void> loadModels(ModelPaths paths) async {
    if (_loaded) return;

    _detector = cv.FaceDetectorYN.fromFile(
      paths.faceModel,
      '',
      // Placeholder input size; reset per-frame in [_detectFaceBoxes].
      (320, 320),
      scoreThreshold: detectionConfig.confidenceThreshold,
      nmsThreshold: detectionConfig.nmsThreshold,
      topK: detectionConfig.topK,
    );
    _ageNet = cv.Net.fromOnnx(paths.ageModel);
    _genderNet = cv.Net.fromOnnx(paths.genderModel);

    _loaded = true;
  }

  /// Detects faces and classifies age/gender/eyes. Returns untracked faces.
  List<DetectedFace> detectAndClassify(cv.Mat frame) {
    final detector = _detector;
    final ageNet = _ageNet;
    final genderNet = _genderNet;
    if (detector == null || ageNet == null || genderNet == null) return [];

    final scale = _processingScale(frame.cols, frame.rows);
    final bool ownsWork;
    final cv.Mat work;
    if (scale == 1.0) {
      work = frame;
      ownsWork = false;
    } else {
      work = cv.resize(
        frame,
        ((frame.cols * scale).round(), (frame.rows * scale).round()),
      );
      ownsWork = true;
    }
    final invScale = 1.0 / scale;

    try {
      final boxes = _detectFaceBoxes(detector, work);
      final faces = <DetectedFace>[];
      var classified = 0;

      for (final box in boxes) {
        if (classified >= kMaxFacesToClassify) break;

        final x1 = (box.x1 * invScale).round().clamp(0, frame.cols - 1);
        final y1 = (box.y1 * invScale).round().clamp(0, frame.rows - 1);
        final w = (box.w * invScale).round().clamp(1, frame.cols - x1);
        final h = (box.h * invScale).round().clamp(1, frame.rows - y1);

        // Scale-independent rejection in original-frame pixels: drop faces too
        // small/low-detail to classify reliably. Done before any per-face work.
        if (w < detectionConfig.minClassifyFacePx ||
            h < detectionConfig.minClassifyFacePx ||
            w * h < detectionConfig.minClassifyFaceArea) {
          continue;
        }

        final lap = _laplacianEyeAnalyzer.analyze(frame, x1, y1, w, h);
        final ear = _earEyeAnalyzer.analyze(frame, x1, y1, w, h);
        final eyes = _eyeCombiner.combinePair(lap, ear);

        // Age: padded square crop of the ORIGINAL frame so the network sees
        // high-quality pixels with training-like context and no aspect
        // distortion when resized to its square input. Behavior unchanged.
        final (ageX, ageY, ageSide) = squareFaceCropRect(
          x1,
          y1,
          w,
          h,
          frame.cols,
          frame.rows,
          padFraction: kAgeGenderCropPadFraction,
        );
        final ageRoi =
            frame.region(cv.Rect(ageX, ageY, ageSide, ageSide));
        final ageLabel = _classifyAge(ageNet, ageRoi);
        ageRoi.dispose();

        // Gender: dedicated, configurable pipeline (margin -> optional
        // alignment -> lighting preprocessing -> inference). Skipped for
        // faces below the configurable minimum size.
        final genderResult = _classifyGenderForBox(
          genderNet: genderNet,
          frame: frame,
          x1: x1,
          y1: y1,
          w: w,
          h: h,
          box: box,
          invScale: invScale,
        );
        classified++;

        final (ex, ey, ew, eh) = expandFaceBox(
          x1,
          y1,
          w,
          h,
          frame.cols,
          frame.rows,
          padFraction: kFaceBoxPadFraction,
        );

        faces.add(
          DetectedFace(
            id: 0, // placeholder, tracker assigns real ID
            x: ex,
            y: ey,
            width: ew,
            height: eh,
            genderLabel: genderResult.$1,
            ageLabel: ageLabel,
            detectionScore: box.score,
            leftEyeState: eyes.$1,
            rightEyeState: eyes.$2,
            maleProbability: genderResult.$2,
            genderConfidence: genderResult.$3,
          ),
        );
      }

      return faces;
    } finally {
      if (ownsWork) work.dispose();
    }
  }

  double _processingScale(int cols, int rows) {
    final maxWidth = detectionConfig.processMaxWidth;
    if (maxWidth <= 0) return 1.0;

    final maxDim = cols > rows ? cols : rows;
    if (maxDim <= maxWidth) return 1.0;
    return maxWidth / maxDim;
  }

  List<_FaceBoxScratch> _detectFaceBoxes(
    cv.FaceDetectorYN detector,
    cv.Mat frame,
  ) {
    final frameWidth = frame.cols;
    final frameHeight = frame.rows;
    final found = <_FaceBoxScratch>[];

    // YuNet requires the network input size to match the image it runs on.
    detector.setInputSize((frameWidth, frameHeight));
    final detections = detector.detect(frame);

    try {
      // Detections are a [num_faces, 15] CV_32F matrix:
      // cols 0-3 = x, y, w, h (pixels); col 14 = score.
      final detCount = detections.rows;
      for (var i = 0; i < detCount; i++) {
        if (found.length >= kMaxFacesToClassify) break;

        final rawX = _matValue(detections, i, 0);
        final rawY = _matValue(detections, i, 1);
        final rawW = _matValue(detections, i, 2);
        final rawH = _matValue(detections, i, 3);
        final score = _matValue(detections, i, 14);
        if (rawX == null ||
            rawY == null ||
            rawW == null ||
            rawH == null ||
            score == null) {
          continue;
        }

        final x1 = rawX.round().clamp(0, frameWidth - 1);
        final y1 = rawY.round().clamp(0, frameHeight - 1);
        final w = rawW.round().clamp(1, frameWidth - x1);
        final h = rawH.round().clamp(1, frameHeight - y1);

        final minBox = detectionConfig.minFaceBoxPx;
        if (w < minBox || h < minBox) continue;

        // YuNet landmarks (work-frame px): cols 4-5 right eye, 6-7 left eye.
        // Used only for optional gender-crop alignment; null when unavailable.
        found.add(
          _FaceBoxScratch(
            x1: x1,
            y1: y1,
            w: w,
            h: h,
            score: score,
            rightEyeX: _matValue(detections, i, 4),
            rightEyeY: _matValue(detections, i, 5),
            leftEyeX: _matValue(detections, i, 6),
            leftEyeY: _matValue(detections, i, 7),
          ),
        );
      }
    } finally {
      detections.dispose();
    }

    found.sort((a, b) => b.score.compareTo(a.score));
    return found;
  }

  String _classifyAge(cv.Net ageNet, cv.Mat faceRoi) {
    final blob = _ageGenderBlob(faceRoi);
    ageNet.setInput(blob);
    final agePreds = ageNet.forward();
    blob.dispose();
    final ageIdx = _argmax(agePreds, kAgeLabels.length);
    agePreds.dispose();
    return kAgeCustomRanges[ageIdx.clamp(0, kAgeCustomRanges.length - 1)];
  }

  /// Builds the enhanced gender crop and runs inference for one face box.
  ///
  /// Returns `(label, maleProbability, confidence)`. When the face is below
  /// [GenderPipelineConfig.minGenderFacePx], inference is skipped and the
  /// result is `('', 0, 0)` so the tracker treats this frame as "no gender".
  (String, double, double) _classifyGenderForBox({
    required cv.Net genderNet,
    required cv.Mat frame,
    required int x1,
    required int y1,
    required int w,
    required int h,
    required _FaceBoxScratch box,
    required double invScale,
  }) {
    final cfg = detectionConfig.gender;
    if (w < cfg.minGenderFacePx || h < cfg.minGenderFacePx) {
      return ('', 0.0, 0.0);
    }

    final (gx, gy, gside) = squareFaceCropRect(
      x1,
      y1,
      w,
      h,
      frame.cols,
      frame.rows,
      padFraction: cfg.faceMarginFraction,
    );
    final region = frame.region(cv.Rect(gx, gy, gside, gside));

    cv.Mat? aligned;
    cv.Mat? preprocessed;
    try {
      var src = region;
      if (cfg.alignmentEnabled &&
          box.rightEyeX != null &&
          box.rightEyeY != null &&
          box.leftEyeX != null &&
          box.leftEyeY != null) {
        // Landmarks are work-frame px; map to original frame, then to crop.
        aligned = _aligner.align(
          region,
          leftEyeX: box.leftEyeX! * invScale - gx,
          leftEyeY: box.leftEyeY! * invScale - gy,
          rightEyeX: box.rightEyeX! * invScale - gx,
          rightEyeY: box.rightEyeY! * invScale - gy,
        );
        if (aligned != null) src = aligned;
      }

      preprocessed = _preprocessor.process(src, cfg);
      return _classifyGender(genderNet, preprocessed);
    } finally {
      preprocessed?.dispose();
      aligned?.dispose();
      region.dispose();
    }
  }

  (String, double, double) _classifyGender(cv.Net genderNet, cv.Mat faceRoi) {
    final blob = _ageGenderBlob(faceRoi);
    genderNet.setInput(blob);
    final preds = genderNet.forward();
    blob.dispose();
    final maleProb = _genderMaleProb(preds);
    preds.dispose();

    final isMale = maleProb >= 0.5;
    final label = isMale ? kGenderLabels[0] : kGenderLabels[1];
    final confidence = isMale ? maleProb : 1.0 - maleProb;
    return (label, maleProb, confidence);
  }

  /// P(male) from the 2-class gender output.
  ///
  /// GoogLeNet gender ONNX ends in a softmax, so when the two outputs already
  /// look like a normalized distribution they are used directly; otherwise
  /// they are treated as logits and softmaxed defensively.
  double _genderMaleProb(cv.Mat preds) {
    final v0 = _flatMatValue(preds, 0) ?? 0.0;
    final v1 = _flatMatValue(preds, 1) ?? 0.0;
    final sum = v0 + v1;
    if (v0 >= 0 && v1 >= 0 && sum > 0.99 && sum < 1.01) {
      return (v0 / sum).clamp(0.0, 1.0);
    }
    final maxV = v0 > v1 ? v0 : v1;
    final e0 = math.exp(v0 - maxV);
    final e1 = math.exp(v1 - maxV);
    final denom = e0 + e1;
    if (denom <= 0) return 0.5;
    return (e0 / denom).clamp(0.0, 1.0);
  }

  cv.Mat _ageGenderBlob(cv.Mat faceRoi) {
    // The ROI is already a square crop, so blobFromImage's own resize to the
    // square network input is the single (distortion-free) resize step.
    return cv.blobFromImage(
      faceRoi,
      scalefactor: 1.0,
      size: (kAgeGenderInputSize, kAgeGenderInputSize),
      mean: cv.Scalar(
        kAgeGenderMean[0],
        kAgeGenderMean[1],
        kAgeGenderMean[2],
      ),
      // GoogLeNet age/gender ONNX models expect RGB input (see reference
      // levi_googlenet.py, which does BGR2RGB before mean subtraction). Frames
      // here are BGR, so swap to RGB; mean is then applied in R,G,B order.
      swapRB: true,
    );
  }

  double? _matValue(cv.Mat mat, int row, int col) {
    try {
      final v = mat.atNum(row, col).toDouble();
      if (!v.isFinite) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  int _argmax(cv.Mat preds, int maxClasses) {
    var bestIdx = 0;
    var bestVal = double.negativeInfinity;
    final limit = preds.total.clamp(1, maxClasses);
    for (var i = 0; i < limit; i++) {
      final v = _flatMatValue(preds, i);
      if (v == null || !v.isFinite || v <= bestVal) continue;
      bestVal = v;
      bestIdx = i;
    }
    return bestIdx;
  }

  double? _flatMatValue(cv.Mat mat, int index) {
    try {
      if (mat.cols > 1 && index < mat.cols) {
        return mat.atNum(0, index).toDouble();
      }
      if (index < mat.rows) {
        return mat.atNum(index, 0).toDouble();
      }
      return mat.atNum(0, index).toDouble();
    } catch (_) {
      return null;
    }
  }
}

class _FaceBoxScratch {
  _FaceBoxScratch({
    required this.x1,
    required this.y1,
    required this.w,
    required this.h,
    required this.score,
    this.rightEyeX,
    this.rightEyeY,
    this.leftEyeX,
    this.leftEyeY,
  });

  final int x1;
  final int y1;
  final int w;
  final int h;
  final double score;

  /// YuNet eye landmarks in detection *work-frame* pixels (null if missing).
  final double? rightEyeX;
  final double? rightEyeY;
  final double? leftEyeX;
  final double? leftEyeY;
}
