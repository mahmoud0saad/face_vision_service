/// A single detected face with a stable session-scoped ID.
class DetectedFace {
  const DetectedFace({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.genderLabel,
    required this.ageLabel,
    required this.detectionScore,
    required this.leftEyeState,
    required this.rightEyeState,
    this.maleProbability = 0.0,
    this.genderConfidence = 0.0,
  });

  final int id;
  final int x;
  final int y;
  final int width;
  final int height;
  final String genderLabel;
  final String ageLabel;
  final double detectionScore;
  final String leftEyeState;
  final String rightEyeState;

  /// Probability that the face is male (`M`), in `[0, 1]`.
  ///
  /// On a raw per-frame face this is the model's softmax output; on a tracked
  /// face it is the temporally smoothed (averaged) probability. `0` when gender
  /// inference was skipped (e.g. face below the minimum size).
  final double maleProbability;

  /// Confidence of the reported [genderLabel], in `[0.5, 1]` once a prediction
  /// exists (`max(maleProbability, 1 - maleProbability)`). `0` when no gender
  /// inference ran. The label is always a concrete `M`/`F`; use this value to
  /// apply your own low-confidence filtering if needed.
  final double genderConfidence;

  Map<String, Object> toMap() => {
        'id': id,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'genderLabel': genderLabel,
        'ageLabel': ageLabel,
        'detectionScore': detectionScore,
        'leftEyeState': leftEyeState,
        'rightEyeState': rightEyeState,
        'maleProbability': maleProbability,
        'genderConfidence': genderConfidence,
      };

  factory DetectedFace.fromMap(Map<Object?, Object?> map) => DetectedFace(
        id: map['id']! as int,
        x: map['x']! as int,
        y: map['y']! as int,
        width: map['width']! as int,
        height: map['height']! as int,
        genderLabel: map['genderLabel']! as String,
        ageLabel: map['ageLabel']! as String,
        detectionScore: (map['detectionScore']! as num).toDouble(),
        leftEyeState: (map['leftEyeState'] as String?) ?? 'unknown',
        rightEyeState: (map['rightEyeState'] as String?) ?? 'unknown',
        maleProbability: (map['maleProbability'] as num?)?.toDouble() ?? 0.0,
        genderConfidence: (map['genderConfidence'] as num?)?.toDouble() ?? 0.0,
      );
}
