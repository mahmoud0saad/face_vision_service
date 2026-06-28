class ModelPaths {
  const ModelPaths({
    required this.faceModel,
    required this.ageModel,
    required this.genderModel,
  });

  /// YuNet face detector ONNX. No separate config file is required.
  final String faceModel;

  /// Age classification ONNX (GoogleNet).
  final String ageModel;

  /// Gender classification ONNX (GoogleNet).
  final String genderModel;

  Map<String, String> toMap() => {
        'faceModel': faceModel,
        'ageModel': ageModel,
        'genderModel': genderModel,
      };

  factory ModelPaths.fromMap(Map<String, String> map) => ModelPaths(
        faceModel: map['faceModel']!,
        ageModel: map['ageModel']!,
        genderModel: map['genderModel']!,
      );
}
