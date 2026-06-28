/// Expands a tight detector box outward, clamped to frame bounds.
(int x, int y, int w, int h) expandFaceBox(
  int x,
  int y,
  int w,
  int h,
  int frameW,
  int frameH, {
  required double padFraction,
}) {
  final padX = (w * padFraction).round();
  final padY = (h * padFraction).round();
  final nx = (x - padX).clamp(0, frameW - 1);
  final ny = (y - padY).clamp(0, frameH - 1);
  final nw = (w + 2 * padX).clamp(1, frameW - nx);
  final nh = (h + 2 * padY).clamp(1, frameH - ny);
  return (nx, ny, nw, nh);
}

/// Computes a padded, square crop centered on a face box, clamped to frame
/// bounds.
///
/// The square side is the longer face edge grown by [padFraction] on every
/// side. The region is shifted to stay inside the frame; the side is only
/// reduced if it would exceed the smaller frame dimension. The result is always
/// square, so resizing it to a square network input introduces no aspect
/// distortion and no border padding is required.
(int x, int y, int side) squareFaceCropRect(
  int x,
  int y,
  int w,
  int h,
  int frameW,
  int frameH, {
  required double padFraction,
}) {
  final cx = x + w / 2.0;
  final cy = y + h / 2.0;
  final base = w > h ? w : h;
  var side = (base * (1.0 + 2 * padFraction)).round();
  final maxSide = frameW < frameH ? frameW : frameH;
  if (side > maxSide) side = maxSide;
  if (side < 1) side = 1;
  final nx = (cx - side / 2.0).round().clamp(0, frameW - side);
  final ny = (cy - side / 2.0).round().clamp(0, frameH - side);
  return (nx, ny, side);
}
