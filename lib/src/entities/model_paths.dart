class ModelPaths {
  const ModelPaths({
    required this.faceModel,
    required this.faceProto,
    required this.ageModel,
    required this.ageProto,
    required this.genderModel,
    required this.genderProto,
  });

  final String faceModel;
  final String faceProto;
  final String ageModel;
  final String ageProto;
  final String genderModel;
  final String genderProto;

  Map<String, String> toMap() => {
        'faceModel': faceModel,
        'faceProto': faceProto,
        'ageModel': ageModel,
        'ageProto': ageProto,
        'genderModel': genderModel,
        'genderProto': genderProto,
      };

  factory ModelPaths.fromMap(Map<String, String> map) => ModelPaths(
        faceModel: map['faceModel']!,
        faceProto: map['faceProto']!,
        ageModel: map['ageModel']!,
        ageProto: map['ageProto']!,
        genderModel: map['genderModel']!,
        genderProto: map['genderProto']!,
      );
}
