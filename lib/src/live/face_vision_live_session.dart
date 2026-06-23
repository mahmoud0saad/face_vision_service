import 'dart:async';

import '../bundled_models.dart';
import '../entities/detected_face.dart';
import '../entities/face_analysis_result.dart';
import '../entities/model_paths.dart';
import '../entities/raw_image.dart';
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

  /// Starts the vision service (if needed), opens the camera, begins internal
  /// confirmation sampling, and emits confirmed results every [intervalSeconds].
  Future<void> start({
    required double intervalSeconds,
    double confirmSamplingIntervalSeconds =
        kDefaultConfirmSamplingIntervalSeconds,
    int deviceIndex = 0,
    bool includePreviewJpeg = false,
    ModelPaths? paths,
    StartupProgressCallback? onStartupProgress,
  }) async {
    if (_running) {
      throw StateError('Session already running. Call stop() first.');
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

    _includePreviewJpeg = includePreviewJpeg;
    _confirmSamplingIntervalSeconds = confirmSamplingIntervalSeconds;
    _cachedResult = null;
    _controller = StreamController<FaceAnalysisResult>.broadcast();

    if (!_client.isRunning) {
      await _client.start(
        paths: paths,
        onStartupProgress: onStartupProgress,
      );
    }

    await _camera.open(deviceIndex: deviceIndex);

    _running = true;
    final emitInterval = Duration(
      milliseconds: (intervalSeconds * 1000).round(),
    );
    _emitTimer = Timer.periodic(emitInterval, (_) => _emitToUser());
    unawaited(_internalSamplingLoop());
  }

  /// Stops capture, closes the camera, and closes the results stream.
  Future<void> stop() async {
    if (!_running) return;

    _running = false;
    _emitTimer?.cancel();
    _emitTimer = null;

    await _camera.close();
    await _controller?.close();
    _controller = null;
    _cachedResult = null;
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
}
