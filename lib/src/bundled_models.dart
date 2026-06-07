import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'entities/model_paths.dart';

/// Loads bundled model files shipped under [lib/assets/models/].
class BundledModels {
  BundledModels._();

  static const bundledAssetNames = [
    'opencv_face_detector.pbtxt',
    'opencv_face_detector_uint8.pb',
    'age_deploy.prototxt',
    'age_net.caffemodel',
    'gender_deploy.prototxt',
    'gender_net.caffemodel',
  ];

  /// Copies bundled models to a writable cache directory and returns [ModelPaths].
  ///
  /// By default reads from the package via [Isolate.resolvePackageUri].
  /// On Flutter, pass [readBytes] that loads
  /// `packages/face_vision_service/assets/models/<file>`.
  static Future<ModelPaths> loadToDisk({
    Future<Uint8List> Function(String relativePath)? readBytes,
    String? cacheDir,
  }) async {
    final reader = readBytes ?? _readFromPackageUri;
    final modelsDir = Directory(
      cacheDir ?? '${Directory.systemTemp.path}/face_vision_models',
    );
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    for (final name in bundledAssetNames) {
      final outFile = File('${modelsDir.path}/$name');
      if (!await outFile.exists()) {
        final bytes = await reader('assets/models/$name');
        await outFile.writeAsBytes(bytes);
      }
    }

    return ModelPaths(
      faceModel: '${modelsDir.path}/opencv_face_detector_uint8.pb',
      faceProto: '${modelsDir.path}/opencv_face_detector.pbtxt',
      ageModel: '${modelsDir.path}/age_net.caffemodel',
      ageProto: '${modelsDir.path}/age_deploy.prototxt',
      genderModel: '${modelsDir.path}/gender_net.caffemodel',
      genderProto: '${modelsDir.path}/gender_deploy.prototxt',
    );
  }

  static Future<Uint8List> _readFromPackageUri(String relativePath) async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:face_vision_service/$relativePath'),
    );
    if (uri == null) {
      throw StateError(
        'Could not resolve package asset: face_vision_service/$relativePath. '
        'On Flutter, pass readBytes to load packages/face_vision_service/$relativePath.',
      );
    }
    final file = File.fromUri(uri);
    if (!await file.exists()) {
      throw StateError('Bundled model file not found: ${file.path}');
    }
    return file.readAsBytes();
  }
}
