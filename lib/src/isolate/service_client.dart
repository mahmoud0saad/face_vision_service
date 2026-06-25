import 'dart:async';
import 'dart:isolate';

import '../bundled_models.dart';
import '../entities/face_analysis_result.dart';
import '../entities/raw_image.dart';
import '../entities/vision_detection_config.dart';
import 'service_isolate_entry.dart';

/// Client that communicates with the vision service isolate.
///
/// Usage:
/// ```dart
/// final client = FaceVisionServiceClient();
/// await client.start();
/// final result = await client.analyze(rawImage);
/// await client.dispose();
/// ```
class FaceVisionServiceClient {
  FaceVisionServiceClient();

  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;
  StreamSubscription<Object?>? _subscription;

  Completer<void>? _initCompleter;
  Completer<FaceAnalysisResult>? _analyzeCompleter;
  Completer<void>? _resetCompleter;
  Completer<void>? _stopCompleter;
  StartupProgressCallback? _startupProgressCallback;

  bool get isRunning => _isolate != null;

  /// Spawns the isolate and loads bundled models from package assets.
  /// Must be called before [analyze].
  ///
  /// Pass [onStartupProgress] to update a loading UI during the slow startup.
  Future<void> start({
    VisionDetectionConfig? detectionConfig,
    StartupProgressCallback? onStartupProgress,
  }) async {
    if (_isolate != null) return;

    _startupProgressCallback = onStartupProgress;
    onStartupProgress?.call('spawning_isolate', null);

    _initCompleter = Completer<void>();
    _mainReceivePort = ReceivePort();

    _subscription = _mainReceivePort!.listen(_onMessage);

    _isolate = await Isolate.spawn(
      serviceIsolateEntry,
      _mainReceivePort!.sendPort,
    );

    // Wait for SendPort handshake
    await _initCompleter!.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () =>
          throw TimeoutException('Vision service isolate init timed out'),
    );

    // Send init command (model prep runs in the worker when possible)
    _initCompleter = Completer<void>();

    final initMessage = <String, Object?>{
      'cmd': 'init',
      if (detectionConfig != null)
        'detectionConfig': detectionConfig.toMap(),
    };

    onStartupProgress?.call('copying_models', 0);
    final modelBytes = await BundledModels.readAllToMemory(
      onProgress: (progress) =>
          onStartupProgress?.call('copying_models', progress),
    );
    initMessage['modelBytes'] = modelBytes;
    _workerSendPort!.send(initMessage);

    await _initCompleter!.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () =>
          throw TimeoutException('Vision service model load timed out'),
    );

    _startupProgressCallback = null;
  }

  /// Analyze a single image. Returns the result with tracked face IDs.
  ///
  /// Set [includePreviewJpeg] to false to skip JPEG encoding for better
  /// performance during live capture.
  Future<FaceAnalysisResult> analyze(
    RawImage image, {
    bool includePreviewJpeg = true,
  }) async {
    if (_workerSendPort == null) {
      throw StateError('Service not started. Call start() first.');
    }

    _analyzeCompleter = Completer<FaceAnalysisResult>();
    _workerSendPort!.send({
      'cmd': 'analyze',
      'bgrBytes': image.bgrBytes,
      'width': image.width,
      'height': image.height,
      'includePreviewJpeg': includePreviewJpeg,
    });

    return _analyzeCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('Analyze timed out'),
    );
  }

  /// Clears face tracking state. New IDs start from 1.
  Future<void> resetTracker() async {
    if (_workerSendPort == null) return;
    _resetCompleter = Completer<void>();
    _workerSendPort!.send({'cmd': 'resetTracker'});
    await _resetCompleter!.future.timeout(const Duration(seconds: 5));
  }

  /// Shuts down the isolate and releases resources.
  Future<void> dispose() async {
    if (_workerSendPort == null) return;
    _stopCompleter = Completer<void>();
    _workerSendPort!.send({'cmd': 'shutdown'});
    await _stopCompleter!.future
        .timeout(const Duration(seconds: 10), onTimeout: () {});
    _cleanup();
  }

  void _onMessage(Object? message) {
    if (message is SendPort) {
      _workerSendPort = message;
      _initCompleter?.complete();
      return;
    }
    if (message is! Map<Object?, Object?>) return;

    final type = message['type'] as String?;
    switch (type) {
      case 'ready':
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _initCompleter!.complete();
        }
        break;
      case 'progress':
        final stage = message['stage'] as String?;
        if (stage != null) {
          _startupProgressCallback?.call(
            stage,
            (message['progress'] as num?)?.toDouble(),
          );
        }
        break;
      case 'result':
        final data = message['data'] as Map<Object?, Object?>?;
        if (data != null && _analyzeCompleter != null) {
          _analyzeCompleter!.complete(FaceAnalysisResult.fromMap(data));
        }
        break;
      case 'ok':
        _resetCompleter?.complete();
        break;
      case 'error':
        final err = StateError(
            message['message']?.toString() ?? 'Vision service error');
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _initCompleter!.completeError(err);
        } else if (_analyzeCompleter != null &&
            !_analyzeCompleter!.isCompleted) {
          _analyzeCompleter!.completeError(err);
        }
        break;
      case 'stopped':
        _stopCompleter?.complete();
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
    _startupProgressCallback = null;
  }
}
