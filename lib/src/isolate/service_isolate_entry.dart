import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../bundled_models.dart';
import '../datasources/opencv_vision_datasource.dart';
import '../entities/face_analysis_result.dart';
import '../entities/model_paths.dart';
import '../entities/vision_detection_config.dart';
import '../tracking/face_tracker.dart';

/// Top-level entry point for the vision service isolate.
void serviceIsolateEntry(SendPort mainSendPort) {
  final workerPort = ReceivePort();
  mainSendPort.send(workerPort.sendPort);

  final vision = OpenCvVisionDatasource();
  // Constructed with defaults; rebuilt on 'init' once the detection config
  // (including gender smoothing/confidence settings) is known.
  var tracker = FaceTracker(maxMissedFrames: 20);

  workerPort.listen((Object? message) async {
    if (message is! Map<Object?, Object?>) return;
    final cmd = message['cmd'] as String?;

    switch (cmd) {
      case 'init':
        try {
          final detectionConfigRaw =
              message['detectionConfig'] as Map<Object?, Object?>?;
          if (detectionConfigRaw != null) {
            final cfg = VisionDetectionConfig.fromMap(detectionConfigRaw);
            vision.detectionConfig = cfg;
            tracker = FaceTracker(
              maxMissedFrames: 20,
              smoothingWindow: cfg.gender.smoothingWindow,
            );
          }
          final paths = await _resolveModelPaths(message, mainSendPort);
          mainSendPort.send({
            'type': 'progress',
            'stage': 'loading_dnn',
            'progress': null,
          });
          await vision.loadModels(paths);
          mainSendPort.send({'type': 'ready'});
        } catch (e) {
          mainSendPort.send({'type': 'error', 'message': e.toString()});
        }
        break;

      case 'analyze':
        try {
          final bytes = message['bgrBytes'] as Uint8List;
          final width = message['width'] as int;
          final height = message['height'] as int;
          final includePreviewJpeg =
              message['includePreviewJpeg'] as bool? ?? true;

          final mat = cv.Mat.fromList(height, width, cv.MatType.CV_8UC3, bytes);
          final rawFaces = vision.detectAndClassify(mat);
          final trackedFaces = tracker.assign(rawFaces);

          Uint8List? previewJpeg;
          if (includePreviewJpeg) {
            final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 80]);
            final (success, jpeg) = cv.imencode('.jpg', mat, params: params);
            previewJpeg = success ? Uint8List.fromList(jpeg) : null;
          }
          mat.dispose();

          final result = FaceAnalysisResult(
            width: width,
            height: height,
            faces: trackedFaces,
            previewJpeg: previewJpeg,
          );

          mainSendPort.send({'type': 'result', 'data': result.toMap()});
        } catch (e) {
          mainSendPort.send({'type': 'error', 'message': e.toString()});
        }
        break;

      case 'resetTracker':
        tracker.reset();
        mainSendPort.send({'type': 'ok'});
        break;

      case 'shutdown':
        mainSendPort.send({'type': 'stopped'});
        workerPort.close();
        Isolate.exit();
    }
  });
}

Future<ModelPaths> _resolveModelPaths(
  Map<Object?, Object?> message,
  SendPort mainSendPort,
) async {
  final modelBytesRaw = message['modelBytes'] as Map<Object?, Object?>?;
  if (modelBytesRaw != null) {
    final filesByName = modelBytesRaw.map(
      (key, value) => MapEntry(key as String, value as Uint8List),
    );
    return BundledModels.writeBytesToDisk(
      filesByName,
      onProgress: (progress) => mainSendPort.send({
        'type': 'progress',
        'stage': 'copying_models',
        'progress': progress,
      }),
    );
  }

  return BundledModels.loadToDisk(
    onProgress: (progress) => mainSendPort.send({
      'type': 'progress',
      'stage': 'copying_models',
      'progress': progress,
    }),
  );
}
