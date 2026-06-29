import 'package:face_vision_service/face_vision_service.dart';
import 'package:face_vision_service/src/camera_isolate_worker.dart';
import 'package:face_vision_service/src/opencv_camera_datasource.dart';
import 'package:test/test.dart';

/// Fake vision client that avoids spawning the real service isolate.
class _FakeClient implements FaceVisionServiceClient {
  _FakeClient({this.startDelay = Duration.zero});

  final Duration startDelay;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start({
    VisionDetectionConfig? detectionConfig,
    StartupProgressCallback? onStartupProgress,
  }) async {
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
    }
    _running = true;
  }

  @override
  Future<FaceAnalysisResult> analyze(
    RawImage image, {
    bool includePreviewJpeg = true,
  }) async {
    return FaceAnalysisResult(
      width: image.width,
      height: image.height,
      faces: const [],
    );
  }

  @override
  Future<void> resetTracker() async {}

  @override
  Future<void> dispose() async {
    _running = false;
  }
}

/// Fake camera that simulates a slow shutdown and records overlapping opens.
class _FakeCamera implements OpenCvCameraDatasource {
  _FakeCamera({this.closeDelay = Duration.zero});

  final Duration closeDelay;

  int openCount = 0;
  int closeCount = 0;
  bool isOpen = false;
  bool _closing = false;

  /// Set true if open() is ever called while the camera is still open or
  /// still closing - i.e. the race condition we are guarding against.
  bool overlapDetected = false;

  @override
  Future<void> open({int deviceIndex = 0}) async {
    if (_closing || isOpen) {
      overlapDetected = true;
    }
    openCount++;
    isOpen = true;
  }

  @override
  Future<CameraFrameData?> readFrame() async => null;

  @override
  Future<void> close() async {
    _closing = true;
    closeCount++;
    if (closeDelay > Duration.zero) {
      await Future<void>.delayed(closeDelay);
    }
    isOpen = false;
    _closing = false;
  }

  @override
  Future<void> shutdown() async {
    isOpen = false;
  }
}

void main() {
  test('isRunning is false but isActive stays true during teardown', () async {
    final camera = _FakeCamera(closeDelay: const Duration(milliseconds: 100));
    final session = FaceVisionLiveSession(
      client: _FakeClient(),
      camera: camera,
    );

    await session.start(intervalSeconds: 0.5);
    expect(session.isRunning, isTrue);
    expect(camera.isOpen, isTrue);

    final stopFuture = session.stop();

    // Teardown is in progress: the session reports it is no longer running,
    // but it must still be active until the camera/isolate are released.
    expect(session.isRunning, isFalse);
    expect(session.isActive, isTrue);
    expect(camera.isOpen, isTrue, reason: 'close delay still in flight');

    await stopFuture;

    expect(session.isActive, isFalse);
    expect(camera.isOpen, isFalse);
    expect(camera.closeCount, 1);
  });

  test('quick stop then start waits for previous teardown (no overlap)',
      () async {
    final camera = _FakeCamera(closeDelay: const Duration(milliseconds: 100));
    final session = FaceVisionLiveSession(
      client: _FakeClient(),
      camera: camera,
    );

    await session.start(intervalSeconds: 0.5);
    expect(camera.openCount, 1);

    // Stop without awaiting, then immediately start again.
    final stopFuture = session.stop();
    final startFuture = session.start(intervalSeconds: 0.5);

    await Future.wait([stopFuture, startFuture]);

    expect(session.isRunning, isTrue);
    expect(camera.isOpen, isTrue);
    expect(
      camera.overlapDetected,
      isFalse,
      reason: 'second open must not begin before the first close finishes',
    );
    expect(camera.openCount, 2);
    expect(camera.closeCount, 1);

    await session.stop();
  });

  test('stop cancels an in-flight start and fully tears down', () async {
    final camera = _FakeCamera(closeDelay: const Duration(milliseconds: 50));
    final session = FaceVisionLiveSession(
      client: _FakeClient(startDelay: const Duration(milliseconds: 200)),
      camera: camera,
    );

    final startFuture = session.start(intervalSeconds: 0.5);
    expect(session.isStarting, isTrue);

    final stopFuture = session.stop();
    await Future.wait([startFuture, stopFuture]);

    expect(session.isRunning, isFalse);
    expect(session.isActive, isFalse);
    expect(camera.isOpen, isFalse);
    expect(camera.openCount, 0, reason: 'camera open should be skipped on cancel');
  });

  test('concurrent stop calls share a single teardown', () async {
    final camera = _FakeCamera(closeDelay: const Duration(milliseconds: 100));
    final session = FaceVisionLiveSession(
      client: _FakeClient(),
      camera: camera,
    );

    await session.start(intervalSeconds: 0.5);

    final stopA = session.stop();
    final stopB = session.stop();
    await Future.wait([stopA, stopB]);

    expect(camera.closeCount, 1);
    expect(session.isActive, isFalse);
  });
}
