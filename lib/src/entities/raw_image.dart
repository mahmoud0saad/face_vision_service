import 'dart:typed_data';

/// BGR pixel buffer input for the vision service.
class RawImage {
  const RawImage({
    required this.bgrBytes,
    required this.width,
    required this.height,
  });

  final Uint8List bgrBytes;
  final int width;
  final int height;
}
