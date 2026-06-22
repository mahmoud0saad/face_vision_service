import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../bundled_models.dart';
import '../entities/face_analysis_result.dart';
import '../entities/model_paths.dart';
import '../entities/raw_image.dart';
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
  FaceVisionServiceClient({
    Future<Uint8List> Function(String relativePath)? readBytes,
  }) : _readBytes = readBytes;

  final Future<Uint8List> Function(String relativePath)? _readBytes;

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

  /// Spawns the isolate and loads models. Must be called before [analyze].
  ///
  /// When [paths] is omitted, loads bundled models from the package.
  /// Pass [onStartupProgress] to update a loading UI during the slow startup.
  Future<void> start({
    ModelPaths? paths,
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

    if (paths != null) {
      onStartupProgress?.call('loading_dnn', null);
      _workerSendPort!.send({'cmd': 'init', 'paths': paths.toMap()});
    } else if (_readBytes != null) {
      onStartupProgress?.call('copying_models', 0);
      final modelBytes = await BundledModels.readAllToMemory(
        readBytes: _readBytes,
        onProgress: (progress) =>
            onStartupProgress?.call('copying_models', progress),
      );
      _workerSendPort!.send({'cmd': 'init', 'modelBytes': modelBytes});
    } else {
      _workerSendPort!.send({'cmd': 'init'});
    }

    await _initCompleter!.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () =>
          throw TimeoutException('Vision service model load timed out'),
    );

    _startupProgressCallback = null;
  }

  /// Analyze a single image. Returns the result with tracked face IDs.
  Future<FaceAnalysisResult> analyze(RawImage image) async {
    if (_workerSendPort == null) {
      throw StateError('Service not started. Call start() first.');
    }

    _analyzeCompleter = Completer<FaceAnalysisResult>();
    _workerSendPort!.send({
      'cmd': 'analyze',
      'bgrBytes': image.bgrBytes,
      'width': image.width,
      'height': image.height,
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
      case 'progress':
        final stage = message['stage'] as String?;
        if (stage != null) {
          _startupProgressCallback?.call(
            stage,
            (message['progress'] as num?)?.toDouble(),
          );
        }
      case 'result':
        final data = message['data'] as Map<Object?, Object?>?;
        if (data != null && _analyzeCompleter != null) {
          _analyzeCompleter!.complete(FaceAnalysisResult.fromMap(data));
        }
      case 'ok':
        _resetCompleter?.complete();
      case 'error':
        final err = StateError(
            message['message']?.toString() ?? 'Vision service error');
        if (_initCompleter != null && !_initCompleter!.isCompleted) {
          _initCompleter!.completeError(err);
        } else if (_analyzeCompleter != null &&
            !_analyzeCompleter!.isCompleted) {
          _analyzeCompleter!.completeError(err);
        }
      case 'stopped':
        _stopCompleter?.complete();
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
