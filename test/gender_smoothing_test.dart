import 'package:face_vision_service/face_vision_service.dart';
import 'package:test/test.dart';

DetectedFace _raw({
  required double maleProb,
  int x = 100,
  int y = 100,
  int w = 120,
  int h = 120,
  String age = '25-35',
}) {
  final confidence = maleProb >= 0.5 ? maleProb : 1.0 - maleProb;
  return DetectedFace(
    id: 0,
    x: x,
    y: y,
    width: w,
    height: h,
    genderLabel: maleProb >= 0.5 ? 'M' : 'F',
    ageLabel: age,
    detectionScore: 0.9,
    leftEyeState: 'open',
    rightEyeState: 'open',
    maleProbability: maleProb,
    genderConfidence: confidence,
  );
}

void main() {
  group('FaceTracker gender smoothing', () {
    test('averages probabilities into a confident M label', () {
      final tracker = FaceTracker(smoothingWindow: 7);
      DetectedFace? out;
      for (var i = 0; i < 5; i++) {
        out = tracker.assign([_raw(maleProb: 0.9)]).single;
      }
      expect(out!.genderLabel, 'M');
      expect(out.genderConfidence, greaterThanOrEqualTo(0.65));
      expect(out.maleProbability, closeTo(0.9, 1e-9));
    });

    test('still emits a concrete M/F even at low confidence', () {
      final tracker = FaceTracker(smoothingWindow: 7);
      // 0.55 male -> confidence 0.55 is low, but the label is never Unknown.
      final out = tracker.assign([_raw(maleProb: 0.55)]).single;
      expect(out.genderLabel, 'M');
      expect(out.genderConfidence, closeTo(0.55, 1e-9));
    });

    test('majority of probabilities decides the smoothed label', () {
      final tracker = FaceTracker(smoothingWindow: 7);
      // Three strong female frames, then one weak male frame.
      tracker.assign([_raw(maleProb: 0.1)]);
      tracker.assign([_raw(maleProb: 0.1)]);
      tracker.assign([_raw(maleProb: 0.1)]);
      final out = tracker.assign([_raw(maleProb: 0.6)]).single;
      // avg = (0.1+0.1+0.1+0.6)/4 = 0.225 -> F with confidence 0.775.
      expect(out.genderLabel, 'F');
      expect(out.genderConfidence, greaterThan(0.6));
    });

    test('skipped-inference frames do not affect the average', () {
      final tracker = FaceTracker(smoothingWindow: 7);
      tracker.assign([_raw(maleProb: 0.95)]);
      // A frame where gender inference was skipped (confidence 0).
      final skipped = DetectedFace(
        id: 0,
        x: 100,
        y: 100,
        width: 120,
        height: 120,
        genderLabel: '',
        ageLabel: '25-35',
        detectionScore: 0.9,
        leftEyeState: 'open',
        rightEyeState: 'open',
      );
      final out = tracker.assign([skipped]).single;
      expect(out.genderLabel, 'M');
      expect(out.maleProbability, closeTo(0.95, 1e-9));
    });

    test('history resets when a tracked face disappears', () {
      final tracker = FaceTracker(
        maxMissedFrames: 2,
        smoothingWindow: 7,
      );
      final first = tracker.assign([_raw(maleProb: 0.95)]).single;
      expect(first.genderLabel, 'M');
      final firstId = first.id;

      // Face disappears long enough for the track (and its history) to drop.
      tracker.assign([]);
      tracker.assign([]);

      final reappeared = tracker.assign([_raw(maleProb: 0.2)]).single;
      expect(reappeared.id, isNot(firstId));
      // Fresh history: averages only 0.2 -> Female, not blended with old 0.95.
      expect(reappeared.genderLabel, 'F');
      expect(reappeared.maleProbability, closeTo(0.2, 1e-9));
    });

    test('window caps how many frames are averaged', () {
      final tracker = FaceTracker(smoothingWindow: 3);
      // Old strong-male frames should age out of a 3-wide window.
      tracker.assign([_raw(maleProb: 0.95)]);
      tracker.assign([_raw(maleProb: 0.95)]);
      tracker.assign([_raw(maleProb: 0.05)]);
      tracker.assign([_raw(maleProb: 0.05)]);
      final out = tracker.assign([_raw(maleProb: 0.05)]).single;
      // Window now holds the three 0.05 frames -> Female.
      expect(out.genderLabel, 'F');
      expect(out.maleProbability, closeTo(0.05, 1e-9));
    });
  });
}
