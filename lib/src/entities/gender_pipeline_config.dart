import '../vision_constants.dart';

/// Tunable parameters for the gender classification accuracy pipeline.
///
/// Groups every knob that improves gender accuracy without retraining the
/// model: input crop margin, lighting preprocessing, optional eye-landmark
/// alignment, an advisory confidence threshold, a minimum face size gate, and
/// temporal smoothing window. The pipeline always emits a concrete M/F label.
///
/// Each enhancement is independently toggleable so they can be A/B tested in
/// isolation. This object is nested inside [VisionDetectionConfig] and is
/// serialized across the worker isolate via [toMap]/[fromMap].
class GenderPipelineConfig {
  const GenderPipelineConfig({
    this.faceMarginFraction = kGenderFaceMarginFraction,
    this.preprocessEnabled = kGenderPreprocessEnabled,
    this.gammaEnabled = kGenderGammaEnabled,
    this.gamma = kGenderGamma,
    this.gammaDarkThreshold = kGenderGammaDarkThreshold,
    this.claheEnabled = kGenderClaheEnabled,
    this.claheClipLimit = kGenderClaheClipLimit,
    this.claheTileGrid = kGenderClaheTileGrid,
    this.autoContrastEnabled = kGenderAutoContrastEnabled,
    this.confidenceThreshold = kGenderConfidenceThreshold,
    this.minGenderFacePx = kMinGenderFacePx,
    this.smoothingWindow = kGenderSmoothingWindow,
    this.alignmentEnabled = kGenderAlignmentEnabled,
  });

  /// Per-side outward expansion of the detected box before cropping, as a
  /// fraction of the box size (e.g. `0.2` = 20% on each side).
  final double faceMarginFraction;

  /// Master switch for all lighting preprocessing on the gender crop.
  final bool preprocessEnabled;

  /// Apply gamma correction to dark crops.
  final bool gammaEnabled;

  /// Gamma exponent for dark-crop correction (>1 brightens mid-tones).
  final double gamma;

  /// Mean luma (0-255) at or above which gamma is skipped.
  final double gammaDarkThreshold;

  /// Apply CLAHE on the luma channel of the gender crop.
  final bool claheEnabled;

  /// CLAHE contrast clip limit.
  final double claheClipLimit;

  /// CLAHE square tile grid size (NxN).
  final int claheTileGrid;

  /// Apply automatic brightness/contrast normalization (convertScaleAbs).
  final bool autoContrastEnabled;

  /// Advisory confidence threshold surfaced for downstream filtering. The
  /// pipeline always emits M/F; this does not force an `Unknown` label.
  final double confidenceThreshold;

  /// Minimum face box width/height (original-frame px) to run gender inference.
  final int minGenderFacePx;

  /// Number of recent per-frame probabilities averaged per tracked face.
  final int smoothingWindow;

  /// Enable optional eye-landmark face alignment before inference.
  final bool alignmentEnabled;

  Map<String, Object?> toMap() => {
        'faceMarginFraction': faceMarginFraction,
        'preprocessEnabled': preprocessEnabled,
        'gammaEnabled': gammaEnabled,
        'gamma': gamma,
        'gammaDarkThreshold': gammaDarkThreshold,
        'claheEnabled': claheEnabled,
        'claheClipLimit': claheClipLimit,
        'claheTileGrid': claheTileGrid,
        'autoContrastEnabled': autoContrastEnabled,
        'confidenceThreshold': confidenceThreshold,
        'minGenderFacePx': minGenderFacePx,
        'smoothingWindow': smoothingWindow,
        'alignmentEnabled': alignmentEnabled,
      };

  factory GenderPipelineConfig.fromMap(Map<Object?, Object?> map) {
    return GenderPipelineConfig(
      faceMarginFraction: (map['faceMarginFraction'] as num?)?.toDouble() ??
          kGenderFaceMarginFraction,
      preprocessEnabled:
          map['preprocessEnabled'] as bool? ?? kGenderPreprocessEnabled,
      gammaEnabled: map['gammaEnabled'] as bool? ?? kGenderGammaEnabled,
      gamma: (map['gamma'] as num?)?.toDouble() ?? kGenderGamma,
      gammaDarkThreshold: (map['gammaDarkThreshold'] as num?)?.toDouble() ??
          kGenderGammaDarkThreshold,
      claheEnabled: map['claheEnabled'] as bool? ?? kGenderClaheEnabled,
      claheClipLimit:
          (map['claheClipLimit'] as num?)?.toDouble() ?? kGenderClaheClipLimit,
      claheTileGrid: map['claheTileGrid'] as int? ?? kGenderClaheTileGrid,
      autoContrastEnabled:
          map['autoContrastEnabled'] as bool? ?? kGenderAutoContrastEnabled,
      confidenceThreshold:
          (map['confidenceThreshold'] as num?)?.toDouble() ??
              kGenderConfidenceThreshold,
      minGenderFacePx: map['minGenderFacePx'] as int? ?? kMinGenderFacePx,
      smoothingWindow:
          map['smoothingWindow'] as int? ?? kGenderSmoothingWindow,
      alignmentEnabled:
          map['alignmentEnabled'] as bool? ?? kGenderAlignmentEnabled,
    );
  }
}
