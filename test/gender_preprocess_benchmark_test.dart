@Tags(['opencv'])
library;

import 'package:face_vision_service/src/datasources/face_aligner.dart';
import 'package:face_vision_service/src/datasources/face_preprocessor.dart';
import 'package:face_vision_service/src/entities/gender_pipeline_config.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:test/test.dart';

/// Builds a dark, low-contrast 224x224 BGR image (mean luma well below the
/// gamma threshold) so every preprocessing branch is actually exercised.
cv.Mat _syntheticDarkFace() {
  const side = 224;
  final data = List<int>.generate(side * side * 3, (i) {
    final pixel = i ~/ 3;
    final x = pixel % side;
    final y = pixel ~/ side;
    // Low-amplitude gradient + texture, kept dark (values ~10..55).
    return (10 + ((x + y) % 30) + ((x * y) % 16)).clamp(0, 60);
  });
  return cv.Mat.fromList(side, side, cv.MatType.CV_8UC3, data);
}

double _benchMs(int iterations, void Function() body) {
  // Warm up.
  body();
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000.0 / iterations;
}

void main() {
  late cv.Mat sample;
  var opencvAvailable = true;

  setUpAll(() {
    try {
      sample = _syntheticDarkFace();
    } catch (e) {
      opencvAvailable = false;
      // ignore: avoid_print
      print('Skipping OpenCV benchmark: native library unavailable ($e)');
    }
  });

  tearDownAll(() {
    if (opencvAvailable) sample.dispose();
  });

  test('FacePreprocessor disabled returns an unmodified-size copy', () {
    if (!opencvAvailable) {
      markTestSkipped('OpenCV native library unavailable');
      return;
    }
    final pre = FacePreprocessor();
    addTearDown(pre.dispose);
    const cfg = GenderPipelineConfig(preprocessEnabled: false);
    final out = pre.process(sample, cfg);
    addTearDown(out.dispose);
    expect(out.rows, sample.rows);
    expect(out.cols, sample.cols);
  });

  test('FacePreprocessor enabled keeps crop dimensions', () {
    if (!opencvAvailable) {
      markTestSkipped('OpenCV native library unavailable');
      return;
    }
    final pre = FacePreprocessor();
    addTearDown(pre.dispose);
    const cfg = GenderPipelineConfig();
    final out = pre.process(sample, cfg);
    addTearDown(out.dispose);
    expect(out.rows, sample.rows);
    expect(out.cols, sample.cols);
    expect(out.channels, 3);
  });

  test('benchmark: per-step preprocessing latency on a 224x224 crop', () {
    if (!opencvAvailable) {
      markTestSkipped('OpenCV native library unavailable');
      return;
    }
    const iterations = 50;
    final pre = FacePreprocessor();
    addTearDown(pre.dispose);
    final aligner = FaceAligner();

    final gammaOnly = const GenderPipelineConfig(
      claheEnabled: false,
      autoContrastEnabled: false,
    );
    final claheOnly = const GenderPipelineConfig(
      gammaEnabled: false,
      autoContrastEnabled: false,
    );
    final autoOnly = const GenderPipelineConfig(
      gammaEnabled: false,
      claheEnabled: false,
      autoContrastEnabled: true,
    );
    final full = const GenderPipelineConfig(autoContrastEnabled: true);

    final gammaMs = _benchMs(iterations, () {
      pre.process(sample, gammaOnly).dispose();
    });
    final claheMs = _benchMs(iterations, () {
      pre.process(sample, claheOnly).dispose();
    });
    final autoMs = _benchMs(iterations, () {
      pre.process(sample, autoOnly).dispose();
    });
    final fullMs = _benchMs(iterations, () {
      pre.process(sample, full).dispose();
    });
    final alignMs = _benchMs(iterations, () {
      final aligned = aligner.align(
        sample,
        leftEyeX: 150,
        leftEyeY: 95,
        rightEyeX: 70,
        rightEyeY: 90,
      );
      aligned?.dispose();
    });

    // ignore: avoid_print
    print('Gender preprocessing latency (avg over $iterations, 224x224 crop):\n'
        '  gamma:        ${gammaMs.toStringAsFixed(3)} ms\n'
        '  clahe:        ${claheMs.toStringAsFixed(3)} ms\n'
        '  autoContrast: ${autoMs.toStringAsFixed(3)} ms\n'
        '  full chain:   ${fullMs.toStringAsFixed(3)} ms\n'
        '  alignment:    ${alignMs.toStringAsFixed(3)} ms');

    // Sanity: each step should be sub-frame-budget on a small crop.
    expect(gammaMs, lessThan(50));
    expect(claheMs, lessThan(50));
    expect(autoMs, lessThan(50));
  });
}
