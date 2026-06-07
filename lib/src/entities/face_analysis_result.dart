import 'dart:typed_data';

import 'detected_face.dart';

/// Full result of analyzing a single image.
class FaceAnalysisResult {
  const FaceAnalysisResult({
    required this.width,
    required this.height,
    required this.faces,
    this.previewJpeg,
  });

  final int width;
  final int height;
  final List<DetectedFace> faces;
  final Uint8List? previewJpeg;

  Map<String, Object?> toMap() => {
        'width': width,
        'height': height,
        'faces': faces.map((f) => f.toMap()).toList(),
        'previewJpeg': previewJpeg,
      };

  factory FaceAnalysisResult.fromMap(Map<Object?, Object?> map) {
    return FaceAnalysisResult(
      width: map['width']! as int,
      height: map['height']! as int,
      faces: (map['faces']! as List)
          .map((e) => DetectedFace.fromMap(e as Map<Object?, Object?>))
          .toList(),
      previewJpeg: map['previewJpeg'] as Uint8List?,
    );
  }
}
