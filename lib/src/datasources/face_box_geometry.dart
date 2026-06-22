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
