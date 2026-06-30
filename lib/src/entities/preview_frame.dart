import 'dart:typed_data';

/// Raw BGR camera frame emitted by [FaceVisionLiveSession] for live preview.
///
/// Carries the unencoded pixel buffer (no JPEG) so the UI can render a smooth
/// live feed independently of the slower face analysis path.
class PreviewFrame {
  const PreviewFrame({
    required this.bgrBytes,
    required this.width,
    required this.height,
  });

  final Uint8List bgrBytes;
  final int width;
  final int height;
}
