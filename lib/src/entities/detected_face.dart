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
      );
}
