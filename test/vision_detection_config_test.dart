import 'package:face_vision_service/face_vision_service.dart';
import 'package:test/test.dart';

void main() {
  test('VisionDetectionConfig defaults favor distant face recall', () {
    const config = VisionDetectionConfig();
    expect(config.processMaxWidth, 960);
    expect(config.confidenceThreshold, 0.5);
    expect(config.nmsThreshold, 0.3);
    expect(config.topK, 5000);
    expect(config.minFaceBoxPx, 10);
    expect(config.minClassifyFacePx, 32);
    expect(config.minClassifyFaceArea, 32 * 32);
  });

  test('VisionDetectionConfig round-trips through map', () {
    const config = VisionDetectionConfig(
      processMaxWidth: 1280,
      confidenceThreshold: 0.35,
      nmsThreshold: 0.4,
      topK: 1000,
      minFaceBoxPx: 8,
      minClassifyFacePx: 48,
      minClassifyFaceArea: 48 * 48,
    );
    final restored = VisionDetectionConfig.fromMap(config.toMap());
    expect(restored.processMaxWidth, 1280);
    expect(restored.confidenceThreshold, 0.35);
    expect(restored.nmsThreshold, 0.4);
    expect(restored.topK, 1000);
    expect(restored.minFaceBoxPx, 8);
    expect(restored.minClassifyFacePx, 48);
    expect(restored.minClassifyFaceArea, 48 * 48);
  });

  test('processMaxWidth 0 disables pre-detection downscale', () {
    const config = VisionDetectionConfig(processMaxWidth: 0);
    expect(config.processMaxWidth, 0);
  });

  test('GenderPipelineConfig exposes documented defaults', () {
    const gender = GenderPipelineConfig();
    expect(gender.faceMarginFraction, 0.2);
    expect(gender.preprocessEnabled, isTrue);
    expect(gender.gammaEnabled, isTrue);
    expect(gender.gamma, 1.2);
    expect(gender.gammaDarkThreshold, 90.0);
    expect(gender.claheEnabled, isTrue);
    expect(gender.claheClipLimit, 2.0);
    expect(gender.claheTileGrid, 8);
    expect(gender.autoContrastEnabled, isFalse);
    expect(gender.confidenceThreshold, 0.65);
    expect(gender.minGenderFacePx, 80);
    expect(gender.smoothingWindow, 7);
    expect(gender.alignmentEnabled, isFalse);
  });

  test('VisionDetectionConfig nests a default GenderPipelineConfig', () {
    const config = VisionDetectionConfig();
    expect(config.gender.faceMarginFraction, 0.2);
    expect(config.gender.minGenderFacePx, 80);
  });

  test('GenderPipelineConfig round-trips through map', () {
    const gender = GenderPipelineConfig(
      faceMarginFraction: 0.25,
      preprocessEnabled: false,
      gammaEnabled: false,
      gamma: 1.5,
      gammaDarkThreshold: 70.0,
      claheEnabled: false,
      claheClipLimit: 3.5,
      claheTileGrid: 4,
      autoContrastEnabled: true,
      confidenceThreshold: 0.8,
      minGenderFacePx: 96,
      smoothingWindow: 10,
      alignmentEnabled: true,
    );
    final restored = GenderPipelineConfig.fromMap(gender.toMap());
    expect(restored.faceMarginFraction, 0.25);
    expect(restored.preprocessEnabled, isFalse);
    expect(restored.gammaEnabled, isFalse);
    expect(restored.gamma, 1.5);
    expect(restored.gammaDarkThreshold, 70.0);
    expect(restored.claheEnabled, isFalse);
    expect(restored.claheClipLimit, 3.5);
    expect(restored.claheTileGrid, 4);
    expect(restored.autoContrastEnabled, isTrue);
    expect(restored.confidenceThreshold, 0.8);
    expect(restored.minGenderFacePx, 96);
    expect(restored.smoothingWindow, 10);
    expect(restored.alignmentEnabled, isTrue);
  });

  test('VisionDetectionConfig round-trips the nested gender config', () {
    const config = VisionDetectionConfig(
      gender: GenderPipelineConfig(
        confidenceThreshold: 0.7,
        minGenderFacePx: 64,
        smoothingWindow: 5,
      ),
    );
    final restored = VisionDetectionConfig.fromMap(config.toMap());
    expect(restored.gender.confidenceThreshold, 0.7);
    expect(restored.gender.minGenderFacePx, 64);
    expect(restored.gender.smoothingWindow, 5);
  });
}
