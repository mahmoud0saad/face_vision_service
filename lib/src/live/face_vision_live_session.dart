import 'dart:async';

import '../bundled_models.dart';
import '../entities/detected_face.dart';
import '../entities/face_analysis_result.dart';
import '../entities/raw_image.dart';
import '../entities/vision_detection_config.dart';
import '../isolate/service_client.dart';
import '../opencv_camera_datasource.dart';
import '../vision_constants.dart';

/// Periodic camera capture and face analysis exposed as a stream.
///
/// Runs internal confirmation sampling between user-facing emissions.
/// Only faces with confirmed gender and age appear on [results].
class FaceVisionLiveSession {
  FaceVisionLiveSession({
    FaceVisionServiceClient? client,
    OpenCvCameraDatasource? camera,
  })  : _client = client ?? FaceVisionServiceClient(),
        _camera = camera ?? OpenCvCameraDatasource(),
        _ownsClient = client == null;

  static const double _minIntervalSeconds = 0.5;

  final FaceVisionServiceClient _client;
  final OpenCvCameraDatasource _camera;
  final bool _ownsClient;

  StreamController<FaceAnalysisResult>? _controller;
  Timer? _emitTimer;
  bool _running = false;
  bool _starting = false;
  bool _stopping = false;
  Future<void>? _teardown;
  int _lifecycleGeneration = 0;
  bool _isAnalyzing = false;
  bool _includePreviewJpeg = false;
  double _confirmSamplingIntervalSeconds =
      kDefaultConfirmSamplingIntervalSeconds;
  FaceAnalysisResult? _cachedResult;

  /// The vision service client used for analysis.
  FaceVisionServiceClient get client => _client;

  /// Emits one [FaceAnalysisResult] per emission interval with confirmed faces only.
  ///
  /// Empty camera frames are skipped during internal sampling. Analysis errors
  /// are forwarded via [Stream.addError].
  Stream<FaceAnalysisResult> get results {
    final controller = _controller;
    if (controller == null) {
      throw StateError('Session not started. Call start() first.');
    }
    return controller.stream;
  }

  bool get isRunning => _running;

  /// True while [start] is in progress (camera / vision service not ready yet).
  bool get isStarting => _starting;

  /// True while [start] is in progress, the capture loop is active, or a
  /// previous session is still tearing down (camera / worker isolate release).
  bool get isActive => _running || _starting || _stopping;

  /// Starts the vision service (if needed), opens the camera, begins internal
  /// confirmation sampling, and emits confirmed results every [intervalSeconds].
  Future<void> start({
    required double intervalSeconds,
    double confirmSamplingIntervalSeconds =
        kDefaultConfirmSamplingIntervalSeconds,
    int deviceIndex = 0,
    bool includePreviewJpeg = false,
    VisionDetectionConfig? detectionConfig,
    StartupProgressCallback? onStartupProgress,
  }) async {
    // Wait for any in-flight teardown to fully release the camera and worker
    // isolate before acquiring them again. This prevents a quick stop -> start
    // from overlapping the previous session's shutdown.
    final pendingTeardown = _teardown;
    if (pendingTeardown != null) {
      await pendingTeardown;
    }

    if (_running) {
      throw StateError('Session already running. Call stop() first.');
    }
    if (_starting) {
      throw StateError('Session start already in progress.');
    }
    if (intervalSeconds < _minIntervalSeconds) {
      throw ArgumentError.value(
        intervalSeconds,
        'intervalSeconds',
        'Must be at least $_minIntervalSeconds',
      );
    }
    if (confirmSamplingIntervalSeconds < kMinConfirmSamplingIntervalSeconds) {
      throw ArgumentError.value(
        confirmSamplingIntervalSeconds,
        'confirmSamplingIntervalSeconds',
        'Must be at least $kMinConfirmSamplingIntervalSeconds',
      );
    }

    final generation = _lifecycleGeneration;
    _starting = true;

    _includePreviewJpeg = includePreviewJpeg;
    _confirmSamplingIntervalSeconds = confirmSamplingIntervalSeconds;
    _cachedResult = null;
    _controller = StreamController<FaceAnalysisResult>.broadcast();

    try {
      if (!_client.isRunning) {
        await _client.start(
          detectionConfig: detectionConfig,
          onStartupProgress: onStartupProgress,
        );
        if (_isCancelled(generation)) return;
      }

      await _camera.open(deviceIndex: deviceIndex);
      if (_isCancelled(generation)) return;

      _running = true;
      final emitInterval = Duration(
        milliseconds: (intervalSeconds * 1000).round(),
      );
      _emitTimer = Timer.periodic(emitInterval, (_) => _emitToUser());
      unawaited(_internalSamplingLoop());
    } finally {
      final cancelled = _isCancelled(generation);
      // Always clear _starting so a waiting stop() can observe completion,
      // even when this start was cancelled (generation advanced).
      _starting = false;
      if (cancelled && !_running) {
        await _abortStart();
      }
    }
  }

  /// Stops capture, closes the camera, and closes the results stream.
  ///
  /// Also cancels an in-flight [start] so callers can shut down before the
  /// session becomes [isRunning].
  Future<void> stop() async {
    // A teardown is already running (from a previous stop or an aborted start);
    // just await the same future so callers don't start a second teardown.
    if (_stopping) {
      await _teardown;
      return;
    }
    if (!_running && !_starting) return;

    // Signal cancellation to any in-flight start().
    _lifecycleGeneration++;

    // Wait for an in-flight start() to observe cancellation and finish.
    while (_starting) {
      await Future<void>.delayed(Duration.zero);
    }

    // A cancelled start() runs its own teardown via _abortStart(); await it
    // instead of starting a second one.
    final abortTeardown = _teardown;
    if (abortTeardown != null) {
      await abortTeardown;
      return;
    }

    // Nothing left to tear down (start was cancelled before opening anything).
    if (!_running) return;

    final teardown = _teardownInternal();
    _teardown = teardown;
    await teardown;
  }

  /// [stop] plus disposes the vision client when this session created it.
  Future<void> dispose() async {
    await stop();
    if (_ownsClient) {
      await _client.dispose();
    }
  }

  Future<void> _internalSamplingLoop() async {
    while (_running) {
      await _captureAndAnalyzeInternal();
      if (!_running) break;
      if (_confirmSamplingIntervalSeconds > 0) {
        await Future.delayed(
          Duration(
            milliseconds: (_confirmSamplingIntervalSeconds * 1000).round(),
          ),
        );
      }
    }
  }

  Future<void> _captureAndAnalyzeInternal() async {
    if (!_running || _isAnalyzing) return;

    _isAnalyzing = true;
    try {
      final frame = await _camera.readFrame();
      if (!_running || frame == null) return;

      final result = await _client.analyze(
        RawImage(
          bgrBytes: frame.bgrBytes,
          width: frame.width,
          height: frame.height,
        ),
        includePreviewJpeg: _includePreviewJpeg,
      );

      if (_running) {
        _cachedResult = result;
      }
    } catch (e, st) {
      final controller = _controller;
      if (_running && controller != null && !controller.isClosed) {
        controller.addError(e, st);
      }
    } finally {
      _isAnalyzing = false;
    }
  }

  void _emitToUser() {
    if (!_running) return;

    final controller = _controller;
    final cached = _cachedResult;
    if (controller == null || controller.isClosed || cached == null) return;

    controller.add(_confirmedOnly(cached));
  }

  static FaceAnalysisResult _confirmedOnly(FaceAnalysisResult result) {
    return FaceAnalysisResult(
      width: result.width,
      height: result.height,
      faces: result.faces.where(_isConfirmed).toList(),
      previewJpeg: result.previewJpeg,
    );
  }

  static bool _isConfirmed(DetectedFace face) =>
      face.genderLabel.isNotEmpty && face.ageLabel.isNotEmpty;

  bool _isCancelled(int generation) => generation != _lifecycleGeneration;

  Future<void> _abortStart() {
    final teardown = _teardownInternal();
    _teardown = teardown;
    return teardown;
  }

  /// Releases the camera (worker isolate) and results stream.
  ///
  /// Marks the session as [_stopping] for its full duration so that
  /// [isActive] stays true and a concurrent [start] awaits completion before
  /// re-acquiring the camera. Stored in [_teardown] by callers.
  Future<void> _teardownInternal() async {
    _stopping = true;
    try {
      _running = false;
      _emitTimer?.cancel();
      _emitTimer = null;

      try {
        await _camera.close();
      } catch (_) {}

      await _controller?.close();
      _controller = null;
      _cachedResult = null;
    } finally {
      _stopping = false;
      _teardown = null;
    }
  }
}

