import 'package:face_vision_service/face_vision_service.dart';
import 'package:test/test.dart';

void main() {
  test('VisionDetectionConfig defaults favor distant face recall', () {
    const config = VisionDetectionConfig();
    expect(config.processMaxWidth, 640);
    expect(config.faceDetectWidth, 300);
    expect(config.faceDetectHeight, 300);
    expect(config.confidenceThreshold, 0.45);
    expect(config.minFaceBoxPx, 10);
  });

  test('VisionDetectionConfig round-trips through map', () {
    const config = VisionDetectionConfig(
      processMaxWidth: 1280,
      faceDetectWidth: 300,
      faceDetectHeight: 300,
      confidenceThreshold: 0.35,
      minFaceBoxPx: 8,
    );
    final restored = VisionDetectionConfig.fromMap(config.toMap());
    expect(restored.processMaxWidth, 1280);
    expect(restored.faceDetectWidth, 300);
    expect(restored.faceDetectHeight, 300);
    expect(restored.confidenceThreshold, 0.35);
    expect(restored.minFaceBoxPx, 8);
  });

  test('processMaxWidth 0 disables pre-detection downscale', () {
    const config = VisionDetectionConfig(processMaxWidth: 0);
    expect(config.processMaxWidth, 0);
  });
}
