/// Raw Adience age buckets produced by `age_googlenet.onnx` (argmax index order).
const List<String> kAgeLabels = [
  '(0-2)',
  '(4-6)',
  '(8-12)',
  '(15-20)',
  '(25-32)',
  '(38-43)',
  '(48-53)',
  '(60-100)',
];

/// Custom display ranges, mapped 1:1 from each [kAgeLabels] index by bucket
/// midpoint. The GoogleNet age model is a fixed 8-bucket classifier, so these
/// are an approximation of the requested ranges rather than a regression value.
const List<String> kAgeCustomRanges = [
  '0-10', // (0-2)
  '0-10', // (4-6)
  '10-15', // (8-12)
  '15-25', // (15-20)
  '25-35', // (25-32)
  '35-50', // (38-43)
  '50-70', // (48-53)
  '50-70', // (60-100)
];

/// Gender labels in `gender_googlenet.onnx` output order (index 0 = Male).
const List<String> kGenderLabels = ['M', 'F'];

/// YuNet face detector score threshold (also exposed via [VisionDetectionConfig]).
///
/// Lowered from 0.6 to 0.5: YuNet assigns lower confidence to small/blurry
/// distant faces, so 0.5 recovers more of them. The extra weak detections are
/// removed downstream by NMS and by the original-frame size/area gate
/// ([kMinClassifyFacePx] / [kMinClassifyFaceArea]).
const double kFaceConfidenceThreshold = 0.6;

/// YuNet non-maximum-suppression IoU threshold.
const double kYuNetNmsThreshold = 0.3;

/// YuNet maximum number of bounding boxes kept before NMS.
const int kYuNetTopK = 5000;

/// Square input size for the GoogleNet age/gender blobs.
const int kAgeGenderInputSize = 224;

/// Per-channel mean subtraction for the GoogleNet age/gender models. The models
/// expect RGB input (the blob is built with swapRB: true on BGR frames), so the
/// mean is applied in R,G,B order to match the reference levi_googlenet.py.
const List<double> kAgeGenderMean = [104.0, 117.0, 123.0];

/// Downscale frames before DNN when the longest side exceeds this value.
///
/// Raised from 640 to 960: YuNet's recall on small/distant faces is bounded by
/// the resolution it actually runs on. A larger work frame keeps distant faces
/// detectable at the cost of more CPU per frame.
const int kProcessMaxWidth = 960;

/// Minimum face box width/height in the detection *work* frame (pixels).
///
/// This is a cheap pre-filter applied on the (possibly downscaled) detection
/// frame. The primary, scale-independent rejection happens later in original
/// frame coordinates via [kMinClassifyFacePx] / [kMinClassifyFaceArea].
const int kMinFaceBoxPx = 10;

/// Minimum face box width/height in the *original* frame (pixels) required to
/// run age/gender classification. Faces smaller than this are dropped, since
/// crops below this size are too low-detail to classify reliably.
const int kMinClassifyFacePx = 32;

/// Minimum face box area in the *original* frame (pixels^2) required to run
/// age/gender classification. Complements [kMinClassifyFacePx] to also reject
/// thin/degenerate boxes.
const int kMinClassifyFaceArea = 32 * 32;

/// Outward padding for the age/gender classification crop (fraction of the
/// square crop's base side, applied to every side).
///
/// The GoogleNet age/gender models (Adience / Levi-Hassner) were trained on
/// face crops that include substantial surrounding context. ~40% margin matches
/// that training distribution far better than a tight detector box. This is kept
/// separate from [kFaceBoxPadFraction] so the reported display box is unchanged.
const double kAgeGenderCropPadFraction = 0.4;

/// Max faces to run age/gender on per frame.
const int kMaxFacesToClassify = 14;

/// Outward padding applied to each side of the raw SSD face box (fraction of box size).
const double kFaceBoxPadFraction = 0.05;

/// Laplacian std-dev threshold: above = eye open, below = eye closed.
const double kEyeOpenStdDevThreshold = 20.0;

/// Min eye crop size (pixels) for reliable classification.
const int kMinEyeCropSize = 12;

/// EAR threshold: above = eye open (typical range 0.20–0.30; tune per device).
const double kEarOpenThreshold = 0.22;

/// Gaussian blur kernel size for eyelid edge detection in eye ROI.
const int kEarBlurKernel = 3;

/// Edge magnitude quantile used as minimum eyelid edge strength.
const double kEarEdgeQuantile = 0.75;

/// Consecutive agreeing analyze results required to lock gender/age for a track.
const int kLabelConfirmFrames =1;

// ---------------------------------------------------------------------------
// Gender pipeline enhancement defaults ([GenderPipelineConfig]).
//
// These tune the dedicated gender classification path (crop margin, lighting
// preprocessing, optional alignment, confidence gating and temporal smoothing)
// without touching the age, eye-state or detection paths.
// ---------------------------------------------------------------------------

/// Per-side outward expansion of the detected box used for the gender crop,
/// as a fraction of the box size. Requirement target is 15-25%; 20% balances
/// added facial context against background noise.
const double kGenderFaceMarginFraction = 0.2;

/// Master switch for gender crop lighting preprocessing.
const bool kGenderPreprocessEnabled = true;

/// Enable gamma correction for dark crops.
const bool kGenderGammaEnabled = true;

/// Gamma exponent applied to dark crops (>1 brightens mid-tones).
const double kGenderGamma = 1.2;

/// Mean luma (0-255) at or above which gamma correction is skipped. Crops
/// brighter than this are already well exposed.
const double kGenderGammaDarkThreshold = 90.0;

/// Enable CLAHE (Contrast Limited Adaptive Histogram Equalization) on the
/// luma channel of the gender crop.
const bool kGenderClaheEnabled = true;

/// CLAHE contrast clip limit. Low values (~2) avoid amplifying noise.
const double kGenderClaheClipLimit = 2.0;

/// CLAHE square tile grid size (NxN) over the crop.
const int kGenderClaheTileGrid = 8;

/// Enable automatic brightness/contrast normalization via convertScaleAbs.
/// Off by default to avoid double-correcting alongside CLAHE.
const bool kGenderAutoContrastEnabled = false;

/// Advisory minimum confidence for a "strong" gender prediction. The pipeline
/// always emits a concrete M/F label; this value is surfaced on the face (as
/// [DetectedFace.genderConfidence]) so downstream consumers can apply their own
/// low-confidence filtering if desired.
const double kGenderConfidenceThreshold = 0.65;

/// Minimum face box width/height (original-frame pixels) required to run gender
/// inference. Smaller faces still get age/eye-state but no gender.
const int kMinGenderFacePx = 80;

/// Number of recent per-frame gender probabilities averaged per tracked face.
const int kGenderSmoothingWindow = 7;

/// Enable optional eye-landmark face alignment before gender inference.
const bool kGenderAlignmentEnabled = false;

/// Default pause between internal confirmation checks in [FaceVisionLiveSession].
const double kDefaultConfirmSamplingIntervalSeconds = 0.1;

/// Minimum [FaceVisionLiveSession.confirmSamplingIntervalSeconds].
const double kMinConfirmSamplingIntervalSeconds = 0.0;
