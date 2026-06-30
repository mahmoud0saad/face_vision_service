import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Optional eye-landmark face alignment (deskew) for the gender crop.
///
/// Rotates a face crop so the eye line is horizontal, which matches the upright
/// faces the GoogLeNet gender model was trained on and removes in-plane roll as
/// a confounder. This is intentionally modular: it is only invoked when
/// alignment is enabled and both eye landmarks are available, and it is a no-op
/// (returns `null`) when the landmarks are degenerate.
class FaceAligner {
  /// Aligns [crop] using crop-relative eye coordinates.
  ///
  /// Returns a NEW rotated `Mat` (caller disposes), or `null` when alignment is
  /// not possible (e.g. coincident eye points). The input is not modified.
  cv.Mat? align(
    cv.Mat crop, {
    required double leftEyeX,
    required double leftEyeY,
    required double rightEyeX,
    required double rightEyeY,
  }) {
    final dx = leftEyeX - rightEyeX;
    final dy = leftEyeY - rightEyeY;
    if (dx == 0 && dy == 0) return null;
    if (!dx.isFinite || !dy.isFinite) return null;

    final angleDeg = math.atan2(dy, dx) * 180.0 / math.pi;
    // Skip the warp for negligible roll to save the allocation/compute.
    if (angleDeg.abs() < 1.0) return null;

    final center = cv.Point2f(crop.cols / 2.0, crop.rows / 2.0);
    final m = cv.getRotationMatrix2D(center, angleDeg, 1.0);
    try {
      return cv.warpAffine(
        crop,
        m,
        (crop.cols, crop.rows),
        flags: cv.INTER_LINEAR,
        borderMode: cv.BORDER_REPLICATE,
      );
    } finally {
      m.dispose();
    }
  }
}
