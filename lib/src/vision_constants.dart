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

const double kFaceConfidenceThreshold = 0.6;

const int kFaceDetectWidth = 128;
const int kFaceDetectHeight = 96;

const int kAgeGenderInputSize = 227;

/// Downscale frames before DNN (major speedup on HD webcams).
const int kProcessMaxWidth = 320;

/// Max faces to run age/gender on per frame.
const int kMaxFacesToClassify = 4;

/// Laplacian std-dev threshold: above = eye open, below = eye closed.
const double kEyeOpenStdDevThreshold = 14.0;

/// Min eye crop size (pixels) for reliable classification.
const int kMinEyeCropSize = 12;
