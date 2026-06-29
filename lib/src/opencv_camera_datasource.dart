import 'camera_isolate_worker.dart';

/// Thin facade over the process-wide shared camera worker isolate.
///
/// Every datasource instance delegates to [CameraIsolateWorker.shared] so the
/// whole app reuses a single camera isolate. [close] releases the device but
/// keeps the isolate warm for the next session; [shutdown] fully tears it down.
class OpenCvCameraDatasource {
  CameraIsolateWorker get _worker => CameraIsolateWorker.shared;

  /// Ownership token for this session's hold on the shared device.
  int? _token;

  Future<void> open({int deviceIndex = 0}) async {
    _token = await _worker.open(deviceIndex: deviceIndex);
  }

  Future<CameraFrameData?> readFrame() {
    final token = _token;
    if (token == null) return Future<CameraFrameData?>.value(null);
    return _worker.grab(token);
  }

  Future<void> close() async {
    final token = _token;
    if (token == null) return;
    _token = null;
    await _worker.close(token);
  }

  /// Fully shuts down the shared camera isolate. Use at app exit.
  Future<void> shutdown() => _worker.dispose();
}
