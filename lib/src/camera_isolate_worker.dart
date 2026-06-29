import 'dart:async';
import 'dart:io' show sleep;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'async_lock.dart';
import 'camera_ownership.dart';

const int kCameraWidth = 640;
const int kCameraHeight = 480;

/// Max attempts to (re)open the device before giving up.
const int _kMaxOpenAttempts = 3;

/// Max warm-up reads after opening before declaring the camera dead.
const int _kMaxWarmupReads = 15;

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

  void releaseCapture() {
    capture?.release();
    capture?.dispose();
    capture = null;
  }

  workerPort.listen((Object? message) {
    if (message is! Map<Object?, Object?>) return;
    final cmd = message['cmd'] as String?;

    switch (cmd) {
      case 'open':
        try {
          final deviceIndex = message['deviceIndex'] as int? ?? 0;
          releaseCapture();

          // Re-acquiring a just-released device can fail transiently; retry.
          cv.VideoCapture? opened;
          for (var attempt = 0; attempt < _kMaxOpenAttempts; attempt++) {
            final cap = cv.VideoCapture.fromDevice(deviceIndex);
            if (cap.isOpened) {
              opened = cap;
              break;
            }
            cap.release();
            cap.dispose();
            sleep(const Duration(milliseconds: 200));
          }
          if (opened == null) {
            throw StateError('Could not open camera at index $deviceIndex');
          }

          opened.set(cv.CAP_PROP_FRAME_WIDTH, kCameraWidth.toDouble());
          opened.set(cv.CAP_PROP_FRAME_HEIGHT, kCameraHeight.toDouble());

          // Warm-up: a freshly opened device (especially right after a release)
          // often returns empty frames for a moment. Don't report success until
          // a real frame flows, otherwise the caller sees a permanently blank
          // camera with no error.
          var gotFrame = false;
          for (var i = 0; i < _kMaxWarmupReads; i++) {
            final (ok, frame) = opened.read();
            final isEmpty = !ok || frame.isEmpty;
            frame.dispose();
            if (!isEmpty) {
              gotFrame = true;
              break;
            }
            sleep(const Duration(milliseconds: 100));
          }
          if (!gotFrame) {
            opened.release();
            opened.dispose();
            throw StateError(
              'Camera opened but produced no frames at index $deviceIndex',
            );
          }

          capture = opened;
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
      case 'release':
        // Release the physical device but keep the isolate alive so the next
        // session can reuse it without a cross-isolate device handoff.
        releaseCapture();
        mainSendPort.send({'type': 'released'});
        break;
      case 'close':
        releaseCapture();
        workerPort.close();
        // Guaranteed delivery of the final reply before the isolate exits.
        Isolate.exit(mainSendPort, {'type': 'stopped'});
    }
  });
}

/// Client that runs OpenCV camera I/O in a background isolate.
///
/// Use [CameraIsolateWorker.shared] so the whole process reuses a single
/// camera isolate. Reopening the device then happens sequentially inside one
/// isolate on the same native handle, instead of a new isolate fighting the
/// previous one over the OS device (which yields a blank, frame-less camera).
class CameraIsolateWorker {
  /// Process-wide shared instance. The isolate is spawned lazily on first
  /// [open] and kept alive across sessions until [dispose].
  static final CameraIsolateWorker shared = CameraIsolateWorker();

  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;
  StreamSubscription<Object?>? _subscription;

  final AsyncLock _lock = AsyncLock();
  final CameraOwnership _ownership = CameraOwnership();

  Completer<void>? _handshakeCompleter;
  Completer<void>? _openCompleter;
  Completer<CameraFrameData?>? _grabCompleter;
  Completer<void>? _releaseCompleter;
  Completer<void>? _closeCompleter;

  /// Opens the device and returns an ownership token. Pass the token to [grab]
  /// and [close] so a superseded session cannot release or read the device.
  Future<int> open({int deviceIndex = 0}) {
    return _lock.synchronized(() async {
      if (_isolate == null) {
        await _spawn();
      }

      // Claim ownership before (re)opening so any older session's in-flight
      // grab/close is treated as stale from here on.
      final token = _ownership.acquire();

      _openCompleter = Completer<void>();
      _workerSendPort!.send({'cmd': 'open', 'deviceIndex': deviceIndex});
      await _openCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Camera open timed out'),
      );
      return token;
    });
  }

  Future<CameraFrameData?> grab(int token) async {
    // Ignore reads from a superseded session: it must not steal frames from the
    // current owner, and it must not clash on the shared grab completer.
    if (_workerSendPort == null || !_ownership.canGrab(token)) return null;

    _grabCompleter = Completer<CameraFrameData?>();
    _workerSendPort!.send({'cmd': 'grab'});
    return _grabCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Camera grab timed out'),
    );
  }

  /// Releases the physical device but keeps the shared isolate alive so the
  /// next [open] can reuse it. Use [dispose] to fully tear down the isolate.
  ///
  /// A stale [token] (from a superseded session) is ignored so it cannot free
  /// the device out from under the session that is currently running.
  Future<void> close(int token) {
    return _lock.synchronized(() async {
      if (_workerSendPort == null) return;
      if (!_ownership.release(token)) return;

      _releaseCompleter = Completer<void>();
      _workerSendPort!.send({'cmd': 'release'});
      await _releaseCompleter!.future
          .timeout(const Duration(seconds: 10), onTimeout: () {});
    });
  }

  /// Fully shuts down the worker isolate (releases the device and exits).
  Future<void> dispose() {
    return _lock.synchronized(() async {
      if (_workerSendPort == null) return;

      _closeCompleter = Completer<void>();
      _workerSendPort!.send({'cmd': 'close'});
      await _closeCompleter!.future
          .timeout(const Duration(seconds: 10), onTimeout: () {});
      _cleanup();
      _ownership.reset();
    });
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
      case 'released':
        _releaseCompleter?.complete();
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
