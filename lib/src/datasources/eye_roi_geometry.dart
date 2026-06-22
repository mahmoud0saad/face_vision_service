import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../vision_constants.dart';

/// Approximate eye crop inside a face bounding box (image coordinates).
cv.Rect? eyeRectFromFaceBox(
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
