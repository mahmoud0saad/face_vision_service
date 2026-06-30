import '../vision_constants.dart';
import 'gender_pipeline_config.dart';

/// Tunable face-detection parameters passed to the vision worker at [init].
class VisionDetectionConfig {
  const VisionDetectionConfig({
    this.processMaxWidth = kProcessMaxWidth,
    this.confidenceThreshold = kFaceConfidenceThreshold,
    this.nmsThreshold = kYuNetNmsThreshold,
    this.topK = kYuNetTopK,
    this.minFaceBoxPx = kMinFaceBoxPx,
    this.minClassifyFacePx = kMinClassifyFacePx,
    this.minClassifyFaceArea = kMinClassifyFaceArea,
    this.gender = const GenderPipelineConfig(),
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

  /// Minimum face box width/height in the original frame (pixels) required to
  /// run age/gender classification. Smaller faces are dropped.
  final int minClassifyFacePx;

  /// Minimum face box area in the original frame (pixels^2) required to run
  /// age/gender classification. Smaller faces are dropped.
  final int minClassifyFaceArea;

  /// Gender accuracy pipeline parameters (crop margin, preprocessing,
  /// alignment, confidence threshold, min size and temporal smoothing).
  final GenderPipelineConfig gender;

  Map<String, Object?> toMap() => {
        'processMaxWidth': processMaxWidth,
        'confidenceThreshold': confidenceThreshold,
        'nmsThreshold': nmsThreshold,
        'topK': topK,
        'minFaceBoxPx': minFaceBoxPx,
        'minClassifyFacePx': minClassifyFacePx,
        'minClassifyFaceArea': minClassifyFaceArea,
        'gender': gender.toMap(),
      };

  factory VisionDetectionConfig.fromMap(Map<Object?, Object?> map) {
    final genderRaw = map['gender'] as Map<Object?, Object?>?;
    return VisionDetectionConfig(
      processMaxWidth: map['processMaxWidth'] as int? ?? kProcessMaxWidth,
      confidenceThreshold: (map['confidenceThreshold'] as num?)?.toDouble() ??
          kFaceConfidenceThreshold,
      nmsThreshold:
          (map['nmsThreshold'] as num?)?.toDouble() ?? kYuNetNmsThreshold,
      topK: map['topK'] as int? ?? kYuNetTopK,
      minFaceBoxPx: map['minFaceBoxPx'] as int? ?? kMinFaceBoxPx,
      minClassifyFacePx:
          map['minClassifyFacePx'] as int? ?? kMinClassifyFacePx,
      minClassifyFaceArea:
          map['minClassifyFaceArea'] as int? ?? kMinClassifyFaceArea,
      gender: genderRaw != null
          ? GenderPipelineConfig.fromMap(genderRaw)
          : const GenderPipelineConfig(),
    );
  }
}
