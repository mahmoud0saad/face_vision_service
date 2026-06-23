import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

const int kCameraWidth = 640;
const int kCameraHeight = 480;

/// Serializable frame returned from the camera worker isolate.
class CameraFrameData {
  const CameraFrameData({
    required this.bgrBytes,
    required this.width,
    required this.height,
  });

  final Uint8List bgrBytes;
  final int width;
  final int height;
}

/// Top-level entry for the camera worker isolate.
void cameraIsolateEntry(SendPort mainSendPort) {
  final workerPort = ReceivePort();
  mainSendPort.send(workerPort.sendPort);

  cv.VideoCapture? capture;

  workerPort.listen((Object? message) {
    if (message is! Map<Object?, Object?>) return;
    final cmd = message['cmd'] as String?;

    switch (cmd) {
      case 'open':
        try {
          final deviceIndex = message['deviceIndex'] as int? ?? 0;
          capture?.release();
          capture?.dispose();
          capture = cv.VideoCapture.fromDevice(deviceIndex);
          if (!capture!.isOpened) {
            throw StateError('Could not open camera at index $deviceIndex');
          }
          capture!.set(cv.CAP_PROP_FRAME_WIDTH, kCameraWidth.toDouble());
          capture!.set(cv.CAP_PROP_FRAME_HEIGHT, kCameraHeight.toDouble());
          mainSendPort.send({'type': 'ok'});
        } catch (e) {
          mainSendPort.send({'type': 'error', 'message': e.toString()});
        }
        break;
      case 'grab':
        try {
          final cap = capture;
          if (cap == null || !cap.isOpened) {
            mainSendPort.send({'type': 'empty'});
            return;
          }
          final (ok, frame) = cap.read();
          if (!ok || frame.isEmpty) {
            frame.dispose();
            mainSendPort.send({'type': 'empty'});
            return;
          }
          final width = frame.cols;
          final height = frame.rows;
          final bytes = Uint8List.fromList(frame.data);
          frame.dispose();
          mainSendPort.send({
            'type': 'frame',
            'width': width,
            'height': height,
            'bgrBytes': bytes,
          });
        } catch (e) {
          mainSendPort.send({'type': 'error', 'message': e.toString()});
        }
        break;
      case 'close':
        capture?.release();
        capture?.dispose();
        capture = null;
        mainSendPort.send({'type': 'stopped'});
        workerPort.close();
        Isolate.exit();
    }
  });
}

/// Client that runs OpenCV camera I/O in a background isolate.
class CameraIsolateWorker {
  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;
  StreamSubscription<Object?>? _subscription;

  Completer<void>? _handshakeCompleter;
  Completer<void>? _openCompleter;
  Completer<CameraFrameData?>? _grabCompleter;
  Completer<void>? _closeCompleter;

  Future<void> open({int deviceIndex = 0}) async {
    if (_isolate == null) {
      await _spawn();
    }

    _openCompleter = Completer<void>();
    _workerSendPort!.send({'cmd': 'open', 'deviceIndex': deviceIndex});
    await _openCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw TimeoutException('Camera open timed out'),
    );
  }

  Future<CameraFrameData?> grab() async {
    if (_workerSendPort == null) return null;

    _grabCompleter = Completer<CameraFrameData?>();
    _workerSendPort!.send({'cmd': 'grab'});
    return _grabCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Camera grab timed out'),
    );
  }

  Future<void> close() async {
    if (_workerSendPort == null) return;

    _closeCompleter = Completer<void>();
    _workerSendPort!.send({'cmd': 'close'});
    await _closeCompleter!.future
        .timeout(const Duration(seconds: 10), onTimeout: () {});
    _cleanup();
  }

  Future<void> _spawn() async {
    _handshakeCompleter = Completer<void>();
    _mainReceivePort = ReceivePort();
    _subscription = _mainReceivePort!.listen(_onMessage);

    _isolate = await Isolate.spawn(
      cameraIsolateEntry,
      _mainReceivePort!.sendPort,
    );

    await _handshakeCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw TimeoutException('Camera isolate handshake timed out'),
    );
  }

  void _onMessage(Object? message) {
    if (message is SendPort) {
      _workerSendPort = message;
      _handshakeCompleter?.complete();
      return;
    }
    if (message is! Map<Object?, Object?>) return;

    final type = message['type'] as String?;
    switch (type) {
      case 'ok':
        _openCompleter?.complete();
        break;
      case 'empty':
        _grabCompleter?.complete(null);
        break;
      case 'frame':
        final bytes = message['bgrBytes'] as Uint8List?;
        final width = message['width'] as int?;
        final height = message['height'] as int?;
        if (bytes != null && width != null && height != null) {
          _grabCompleter?.complete(
            CameraFrameData(
              bgrBytes: bytes,
              width: width,
              height: height,
            ),
          );
        } else {
          _grabCompleter?.complete(null);
        }
        break;
      case 'error':
        final err = StateError(
          message['message']?.toString() ?? 'Camera worker error',
        );
        if (_openCompleter != null && !_openCompleter!.isCompleted) {
          _openCompleter!.completeError(err);
        } else if (_grabCompleter != null && !_grabCompleter!.isCompleted) {
          _grabCompleter!.completeError(err);
        }
        break;
      case 'stopped':
        _closeCompleter?.complete();
        break;
    }
  }

  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
  }
}
