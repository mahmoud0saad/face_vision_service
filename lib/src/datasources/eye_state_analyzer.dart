import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../vision_constants.dart';
import 'eye_roi_geometry.dart';

/// Estimates open/closed per eye using Laplacian sharpness in the eye region.
class EyeStateAnalyzer {
  (String left, String right) analyze(
    cv.Mat frame,
    int fx,
    int fy,
    int fw,
    int fh,
  ) {
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
    final rect = eyeRectFromFaceBox(
      frame.cols,
      frame.rows,
      fx,
      fy,
      fw,
      fh,
      isLeft: isLeft,
    );
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
