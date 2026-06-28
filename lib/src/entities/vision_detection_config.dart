import '../vision_constants.dart';

/// Tunable face-detection parameters passed to the vision worker at [init].
class VisionDetectionConfig {
  const VisionDetectionConfig({
    this.processMaxWidth = kProcessMaxWidth,
    this.confidenceThreshold = kFaceConfidenceThreshold,
    this.nmsThreshold = kYuNetNmsThreshold,
    this.topK = kYuNetTopK,
    this.minFaceBoxPx = kMinFaceBoxPx,
  });

  /// Downscale frames so the longest side is at most this many pixels before
  /// detection. Set to `0` to disable downscaling.
  final int processMaxWidth;

  /// YuNet score threshold; detections below this are discarded.
  final double confidenceThreshold;

  /// YuNet non-maximum-suppression IoU threshold.
  final double nmsThreshold;

  /// YuNet maximum number of bounding boxes kept before NMS.
  final int topK;

  /// Minimum face box width/height in the detection work frame (pixels).
  final int minFaceBoxPx;

  Map<String, Object?> toMap() => {
        'processMaxWidth': processMaxWidth,
        'confidenceThreshold': confidenceThreshold,
        'nmsThreshold': nmsThreshold,
        'topK': topK,
        'minFaceBoxPx': minFaceBoxPx,
      };

  factory VisionDetectionConfig.fromMap(Map<Object?, Object?> map) {
    return VisionDetectionConfig(
      processMaxWidth: map['processMaxWidth'] as int? ?? kProcessMaxWidth,
      confidenceThreshold: (map['confidenceThreshold'] as num?)?.toDouble() ??
          kFaceConfidenceThreshold,
      nmsThreshold:
          (map['nmsThreshold'] as num?)?.toDouble() ?? kYuNetNmsThreshold,
      topK: map['topK'] as int? ?? kYuNetTopK,
      minFaceBoxPx: map['minFaceBoxPx'] as int? ?? kMinFaceBoxPx,
    );
  }
}
