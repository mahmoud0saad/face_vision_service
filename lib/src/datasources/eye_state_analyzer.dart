import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../vision_constants.dart';

/// Estimates open/closed per eye using Laplacian sharpness in the eye region.
class EyeStateAnalyzer {
  (String left, String right) analyze(
      cv.Mat frame, int fx, int fy, int fw, int fh) {
    final left = _classifyEye(frame, fx, fy, fw, fh, isLeft: true);
    final right = _classifyEye(frame, fx, fy, fw, fh, isLeft: false);
    return (left, right);
  }

  String _classifyEye(
    cv.Mat frame,
    int fx,
    int fy,
    int fw,
    int fh, {
    required bool isLeft,
  }) {
    final rect =
        _eyeRect(frame.cols, frame.rows, fx, fy, fw, fh, isLeft: isLeft);
    if (rect == null) return 'unknown';

    final roi = frame.region(rect);
    try {
      final score = _laplacianStdDev(roi);
      if (score < 0) return 'unknown';
      return score >= kEyeOpenStdDevThreshold ? 'open' : 'closed';
    } finally {
      roi.dispose();
    }
  }

  cv.Rect? _eyeRect(
    int frameW,
    int frameH,
    int fx,
    int fy,
    int fw,
    int fh, {
    required bool isLeft,
  }) {
    final ex = isLeft ? fx + (fw * 0.06).round() : fx + (fw * 0.54).round();
    final ey = fy + (fh * 0.22).round();
    final ew = (fw * 0.36).round();
    final eh = (fh * 0.32).round();
    if (ew < kMinEyeCropSize || eh < kMinEyeCropSize) return null;

    final x = ex.clamp(0, frameW - 1);
    final y = ey.clamp(0, frameH - 1);
    final w = ew.clamp(kMinEyeCropSize, frameW - x);
    final h = eh.clamp(kMinEyeCropSize, frameH - y);
    return cv.Rect(x, y, w, h);
  }

  double _laplacianStdDev(cv.Mat bgrRoi) {
    final gray = cv.cvtColor(bgrRoi, cv.COLOR_BGR2GRAY);
    final lap = cv.laplacian(gray, cv.MatType.CV_64F, ksize: 3);
    gray.dispose();

    try {
      final (mean, stddev) = cv.meanStdDev(lap);
      mean.dispose();
      final v = stddev.val1;
      stddev.dispose();
      if (!v.isFinite) return -1;
      return v;
    } finally {
      lap.dispose();
    }
  }
}
