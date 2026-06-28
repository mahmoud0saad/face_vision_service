import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../entities/detected_face.dart';
import '../entities/model_paths.dart';
import '../entities/vision_detection_config.dart';
import '../vision_constants.dart';
import 'ear_eye_state_analyzer.dart';
import 'eye_state_analyzer.dart';
import 'eye_state_combiner.dart';
import 'face_box_geometry.dart';

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

        final lap = _laplacianEyeAnalyzer.analyze(frame, x1, y1, w, h);
        final ear = _earEyeAnalyzer.analyze(frame, x1, y1, w, h);
        final eyes = _eyeCombiner.combinePair(lap, ear);

        final roi = frame.region(cv.Rect(x1, y1, w, h));
        final labels = _classifyAgeGender(ageNet, genderNet, roi);
        roi.dispose();
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
            genderLabel: labels.$1,
            ageLabel: labels.$2,
            detectionScore: box.score,
            leftEyeState: eyes.$1,
            rightEyeState: eyes.$2,
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

        found.add(_FaceBoxScratch(x1: x1, y1: y1, w: w, h: h, score: score));
      }
    } finally {
      detections.dispose();
    }

    found.sort((a, b) => b.score.compareTo(a.score));
    return found;
  }

  (String, String) _classifyAgeGender(
    cv.Net ageNet,
    cv.Net genderNet,
    cv.Mat faceRoi,
  ) {
    final blob = _ageGenderBlob(faceRoi);
    genderNet.setInput(blob);
    final genderPreds = genderNet.forward();
    final genderIdx = _argmax(genderPreds, kGenderLabels.length);
    genderPreds.dispose();

    ageNet.setInput(blob);
    final agePreds = ageNet.forward();
    blob.dispose();
    final ageIdx = _argmax(agePreds, kAgeLabels.length);
    agePreds.dispose();

    return (
      kGenderLabels[genderIdx.clamp(0, kGenderLabels.length - 1)],
      kAgeCustomRanges[ageIdx.clamp(0, kAgeCustomRanges.length - 1)],
    );
  }

  cv.Mat _ageGenderBlob(cv.Mat faceRoi) {
    final resized =
        cv.resize(faceRoi, (kAgeGenderInputSize, kAgeGenderInputSize));
    final blob = cv.blobFromImage(
      resized,
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
    resized.dispose();
    return blob;
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
  });

  final int x1;
  final int y1;
  final int w;
  final int h;
  final double score;
}
