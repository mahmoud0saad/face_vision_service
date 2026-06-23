import 'camera_isolate_worker.dart';

class OpenCvCameraDatasource {
  final CameraIsolateWorker _worker = CameraIsolateWorker();

  Future<void> open({int deviceIndex = 0}) =>
      _worker.open(deviceIndex: deviceIndex);

  Future<CameraFrameData?> readFrame() => _worker.grab();

  Future<void> close() => _worker.close();
}
