import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../datasources/opencv_vision_datasource.dart';
import '../entities/face_analysis_result.dart';
import '../entities/model_paths.dart';
import '../tracking/face_tracker.dart';

/// Top-level entry point for the vision service isolate.
void serviceIsolateEntry(SendPort mainSendPort) {
  final workerPort = ReceivePort();
  mainSendPort.send(workerPort.sendPort);

  final vision = OpenCvVisionDatasource();
  final tracker = FaceTracker();

  workerPort.listen((Object? message) async {
    if (message is! Map<Object?, Object?>) return;
    final cmd = message['cmd'] as String?;

    switch (cmd) {
      case 'init':
        try {
          final pathsRaw = message['paths'] as Map<Object?, Object?>;
          final paths = ModelPaths.fromMap(pathsRaw.cast<String, String>());
          await vision.loadModels(paths);
          mainSendPort.send({'type': 'ready'});
        } catch (e) {
          mainSendPort.send({'type': 'error', 'message': e.toString()});
        }

      case 'analyze':
        try {
          final bytes = message['bgrBytes'] as Uint8List;
          final width = message['width'] as int;
          final height = message['height'] as int;

          final mat = cv.Mat.fromList(height, width, cv.MatType.CV_8UC3, bytes);
          final rawFaces = vision.detectAndClassify(mat);
          final trackedFaces = tracker.assign(rawFaces);

          // Encode a JPEG preview
          final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 80]);
          final (success, jpeg) = cv.imencode('.jpg', mat, params: params);
          mat.dispose();

          final result = FaceAnalysisResult(
            width: width,
            height: height,
            faces: trackedFaces,
            previewJpeg: success ? Uint8List.fromList(jpeg) : null,
          );

          mainSendPort.send({'type': 'result', 'data': result.toMap()});
        } catch (e) {
          mainSendPort.send({'type': 'error', 'message': e.toString()});
        }

      case 'resetTracker':
        tracker.reset();
        mainSendPort.send({'type': 'ok'});

      case 'shutdown':
        mainSendPort.send({'type': 'stopped'});
        workerPort.close();
        Isolate.exit();
    }
  });
}
