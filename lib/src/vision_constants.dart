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

const List<String> kGenderLabels = ['M', 'F'];

const double kFaceConfidenceThreshold = 0.45;

const int kFaceDetectWidth = 300;
const int kFaceDetectHeight = 300;

const int kAgeGenderInputSize = 227;

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
const int kLabelConfirmFrames =5;

/// Default pause between internal confirmation checks in [FaceVisionLiveSession].
const double kDefaultConfirmSamplingIntervalSeconds = 0.1;

/// Minimum [FaceVisionLiveSession.confirmSamplingIntervalSeconds].
const double kMinConfirmSamplingIntervalSeconds = 0.0;
