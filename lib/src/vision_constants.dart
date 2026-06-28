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
const int kProcessMaxWidth = 640;

/// Minimum face box width/height in the detection work frame (pixels).
const int kMinFaceBoxPx = 10;

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
const int kLabelConfirmFrames =3;

/// Default pause between internal confirmation checks in [FaceVisionLiveSession].
const double kDefaultConfirmSamplingIntervalSeconds = 0.1;

/// Minimum [FaceVisionLiveSession.confirmSamplingIntervalSeconds].
const double kMinConfirmSamplingIntervalSeconds = 0.0;
