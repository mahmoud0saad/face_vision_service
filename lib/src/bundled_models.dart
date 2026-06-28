import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'entities/model_paths.dart';

/// Reports startup stage and optional progress in `[0, 1]`.
typedef StartupProgressCallback = void Function(String stage, double? progress);

/// Loads bundled model files shipped under [lib/assets/models/].
class BundledModels {
  BundledModels._();

  static const _packageAssetPrefix = 'packages/face_vision_service';
  static const _assetDir = 'lib/assets/models';

  static const bundledAssetNames = [
    'face_detection_yunet_2023mar.onnx',
    'age_googlenet.onnx',
    'gender_googlenet.onnx',
  ];

  /// Reads a bundled model file from the package Flutter assets.
  static Future<Uint8List> readFromPackageAssets(String relativePath) async {
    final data = await rootBundle.load('$_packageAssetPrefix/$relativePath');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static String _assetPath(String name) => '$_assetDir/$name';

  /// Copies bundled models to a writable cache directory and returns [ModelPaths].
  ///
  /// By default reads from the package via [Isolate.resolvePackageUri].
  static Future<ModelPaths> loadToDisk({
    Future<Uint8List> Function(String relativePath)? readBytes,
    String? cacheDir,
    void Function(double progress)? onProgress,
  }) async {
    final reader = readBytes ?? _readFromPackageUri;
    final modelsDir = await _ensureCacheDir(cacheDir);
    final total = bundledAssetNames.length;

    for (var i = 0; i < bundledAssetNames.length; i++) {
      final name = bundledAssetNames[i];
      final outFile = File('${modelsDir.path}/$name');
      if (!await outFile.exists()) {
        final bytes = await reader(_assetPath(name));
        await outFile.writeAsBytes(bytes);
      }
      await Future<void>.delayed(Duration.zero);
      onProgress?.call((i + 1) / total);
    }

    return _pathsForDir(modelsDir.path);
  }

  /// Reads all bundled models into memory from package assets.
  static Future<Map<String, Uint8List>> readAllToMemory({
    Future<Uint8List> Function(String relativePath)? readBytes,
    void Function(double progress)? onProgress,
  }) async {
    final reader = readBytes ?? readFromPackageAssets;
    final result = <String, Uint8List>{};
    final total = bundledAssetNames.length;

    for (var i = 0; i < bundledAssetNames.length; i++) {
      final name = bundledAssetNames[i];
      result[name] = await reader(_assetPath(name));
      await Future<void>.delayed(Duration.zero);
      onProgress?.call((i + 1) / total);
    }

    return result;
  }

  /// Writes pre-read model bytes to the cache directory and returns [ModelPaths].
  static Future<ModelPaths> writeBytesToDisk(
    Map<String, Uint8List> filesByName, {
    String? cacheDir,
    void Function(double progress)? onProgress,
  }) async {
    final modelsDir = await _ensureCacheDir(cacheDir);
    final total = bundledAssetNames.length;

    for (var i = 0; i < bundledAssetNames.length; i++) {
      final name = bundledAssetNames[i];
      final bytes = filesByName[name];
      if (bytes == null) {
        throw StateError('Missing bundled model bytes for $name');
      }
      final outFile = File('${modelsDir.path}/$name');
      if (!await outFile.exists()) {
        await outFile.writeAsBytes(bytes);
      }
      await Future<void>.delayed(Duration.zero);
      onProgress?.call((i + 1) / total);
    }

    return _pathsForDir(modelsDir.path);
  }

  static Future<Directory> _ensureCacheDir(String? cacheDir) async {
    final modelsDir = Directory(
      cacheDir ?? '${Directory.systemTemp.path}/face_vision_models',
    );
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  static ModelPaths _pathsForDir(String dirPath) => ModelPaths(
        faceModel: '$dirPath/face_detection_yunet_2023mar.onnx',
        ageModel: '$dirPath/age_googlenet.onnx',
        genderModel: '$dirPath/gender_googlenet.onnx',
      );

  static Future<Uint8List> _readFromPackageUri(String relativePath) async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:face_vision_service/$relativePath'),
    );
    if (uri == null) {
      throw StateError(
        'Could not resolve package asset: face_vision_service/$relativePath.',
      );
    }
    final file = File.fromUri(uri);
    if (!await file.exists()) {
      throw StateError('Bundled model file not found: ${file.path}');
    }
    return file.readAsBytes();
  }
}
