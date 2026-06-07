import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../entities/detected_face.dart';
import '../entities/model_paths.dart';
import '../vision_constants.dart';
import 'eye_state_analyzer.dart';

class OpenCvVisionDatasource {
  cv.Net? _faceNet;
  cv.Net? _ageNet;
  cv.Net? _genderNet;
  bool _loaded = false;

  final EyeStateAnalyzer _eyeAnalyzer = EyeStateAnalyzer();

  Future<void> loadModels(ModelPaths paths) async {
    if (_loaded) return;

    _faceNet = cv.Net.fromTensorflow(
      paths.faceModel,
      config: paths.faceProto,
    );
    _ageNet = cv.Net.fromCaffe(paths.ageProto, paths.ageModel);
    _genderNet = cv.Net.fromCaffe(paths.genderProto, paths.genderModel);

    _loaded = true;
  }

  /// Detects faces and classifies age/gender/eyes. Returns untracked faces.
  List<DetectedFace> detectAndClassify(cv.Mat frame) {
    final faceNet = _faceNet;
    final ageNet = _ageNet;
    final genderNet = _genderNet;
    if (faceNet == null || ageNet == null || genderNet == null) return [];

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
      final boxes = _detectFaceBoxes(faceNet, work);
      final faces = <DetectedFace>[];
      var classified = 0;

      for (final box in boxes) {
        if (classified >= kMaxFacesToClassify) break;

        final x1 = (box.x1 * invScale).round();
        final y1 = (box.y1 * invScale).round();
        final w = (box.w * invScale).round().clamp(1, frame.cols - x1);
        final h = (box.h * invScale).round().clamp(1, frame.rows - y1);

        final eyes = _eyeAnalyzer.analyze(frame, x1, y1, w, h);

        final roi = frame.region(cv.Rect(x1, y1, w, h));
        final labels = _classifyAgeGender(ageNet, genderNet, roi);
        roi.dispose();
        classified++;

        faces.add(
          DetectedFace(
            id: 0, // placeholder, tracker assigns real ID
            x: x1,
            y: y1,
            width: w,
            height: h,
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
    final maxDim = cols > rows ? cols : rows;
    if (maxDim <= kProcessMaxWidth) return 1.0;
    return kProcessMaxWidth / maxDim;
  }

  List<_FaceBoxScratch> _detectFaceBoxes(cv.Net faceNet, cv.Mat frame) {
    final frameHeight = frame.rows;
    final frameWidth = frame.cols;
    final found = <_FaceBoxScratch>[];

    final faceBlob = cv.blobFromImage(
      frame,
      scalefactor: 1.0,
      size: (kFaceDetectWidth, kFaceDetectHeight),
      mean: cv.Scalar(104, 177, 123),
      swapRB: false,
    );
    faceNet.setInput(faceBlob);
    final detections = faceNet.forward();
    faceBlob.dispose();

    final (detGrid, ownsGrid) = _asDetectionGrid(detections);
    final detCount = detGrid.rows;

    try {
      for (var i = 0; i < detCount; i++) {
        if (found.length >= kMaxFacesToClassify) break;

        final confidence = _detectionValue(detGrid, i, 2);
        if (confidence == null || confidence < kFaceConfidenceThreshold) {
          continue;
        }

        final x1 = _normToPixel(_detectionValue(detGrid, i, 3), frameWidth);
        final y1 = _normToPixel(_detectionValue(detGrid, i, 4), frameHeight);
        final x2 = _normToPixel(_detectionValue(detGrid, i, 5), frameWidth);
        final y2 = _normToPixel(_detectionValue(detGrid, i, 6), frameHeight);
        if (x1 == null || y1 == null || x2 == null || y2 == null) continue;
        if (x2 <= x1 || y2 <= y1) continue;

        final w = (x2 - x1).clamp(1, frameWidth - x1);
        final h = (y2 - y1).clamp(1, frameHeight - y1);
        if (w < 20 || h < 20) continue;

        found.add(
            _FaceBoxScratch(x1: x1, y1: y1, w: w, h: h, score: confidence));
      }
    } finally {
      if (ownsGrid) detGrid.dispose();
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
      kAgeLabels[ageIdx.clamp(0, kAgeLabels.length - 1)],
    );
  }

  cv.Mat _ageGenderBlob(cv.Mat faceRoi) {
    final resized =
        cv.resize(faceRoi, (kAgeGenderInputSize, kAgeGenderInputSize));
    final blob = cv.blobFromImage(
      resized,
      scalefactor: 1.0,
      size: (kAgeGenderInputSize, kAgeGenderInputSize),
      mean: cv.Scalar(78.4263, 87.7689, 114.8958),
      swapRB: false,
    );
    resized.dispose();
    return blob;
  }

  (cv.Mat, bool) _asDetectionGrid(cv.Mat detections) {
    if (detections.rows > 1 && detections.cols >= 7) {
      return (detections, false);
    }
    final n = detections.size.length > 2 ? detections.size[2] : 0;
    if (n > 0) {
      return (detections.reshape(1, n), true);
    }
    return (detections, false);
  }

  double? _detectionValue(cv.Mat detections, int row, int col) {
    try {
      final v = detections.atNum(row, col).toDouble();
      if (!v.isFinite) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  int? _normToPixel(double? norm, int frameSize) {
    if (norm == null || !norm.isFinite || norm < 0 || norm > 1) return null;
    return (norm * frameSize).round().clamp(0, frameSize - 1);
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
