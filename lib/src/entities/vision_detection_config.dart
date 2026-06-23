import '../vision_constants.dart';

/// Tunable face-detection parameters passed to the vision worker at [init].
class VisionDetectionConfig {
  const VisionDetectionConfig({
    this.processMaxWidth = kProcessMaxWidth,
    this.faceDetectWidth = kFaceDetectWidth,
    this.faceDetectHeight = kFaceDetectHeight,
    this.confidenceThreshold = kFaceConfidenceThreshold,
    this.minFaceBoxPx = kMinFaceBoxPx,
  });

  final int processMaxWidth;
  final int faceDetectWidth;
  final int faceDetectHeight;
  final double confidenceThreshold;
  final int minFaceBoxPx;

  Map<String, Object?> toMap() => {
        'processMaxWidth': processMaxWidth,
        'faceDetectWidth': faceDetectWidth,
        'faceDetectHeight': faceDetectHeight,
        'confidenceThreshold': confidenceThreshold,
        'minFaceBoxPx': minFaceBoxPx,
      };

  factory VisionDetectionConfig.fromMap(Map<Object?, Object?> map) {
    return VisionDetectionConfig(
      processMaxWidth: map['processMaxWidth'] as int? ?? kProcessMaxWidth,
      faceDetectWidth: map['faceDetectWidth'] as int? ?? kFaceDetectWidth,
      faceDetectHeight: map['faceDetectHeight'] as int? ?? kFaceDetectHeight,
      confidenceThreshold:
          (map['confidenceThreshold'] as num?)?.toDouble() ??
              kFaceConfidenceThreshold,
      minFaceBoxPx: map['minFaceBoxPx'] as int? ?? kMinFaceBoxPx,
    );
  }
}
