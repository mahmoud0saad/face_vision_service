import 'package:face_vision_service/src/datasources/face_box_geometry.dart';
import 'package:test/test.dart';

void main() {
  group('squareFaceCropRect margin', () {
    test('expands the box by the configured margin on each side', () {
      // 100px box centered in a large frame, 20% margin -> side = 100 * 1.4.
      final (x, y, side) = squareFaceCropRect(
        450,
        450,
        100,
        100,
        1000,
        1000,
        padFraction: 0.2,
      );
      expect(side, 140);
      // Stays centered on the original box center (500, 500).
      expect(x, 430);
      expect(y, 430);
    });

    test('clamps the expanded rectangle to the frame boundaries', () {
      // Box hugging the top-left corner; the padded square must not go < 0.
      final (x, y, side) = squareFaceCropRect(
        0,
        0,
        100,
        100,
        1000,
        1000,
        padFraction: 0.25,
      );
      expect(x, 0);
      expect(y, 0);
      expect(x + side, lessThanOrEqualTo(1000));
      expect(y + side, lessThanOrEqualTo(1000));
    });

    test('a larger margin yields a larger crop side', () {
      final (_, __, smallSide) =
          squareFaceCropRect(450, 450, 100, 100, 1000, 1000, padFraction: 0.15);
      final (___, ____, bigSide) =
          squareFaceCropRect(450, 450, 100, 100, 1000, 1000, padFraction: 0.25);
      expect(bigSide, greaterThan(smallSide));
    });

    test('side never exceeds the smaller frame dimension', () {
      final (x, y, side) = squareFaceCropRect(
        10,
        10,
        300,
        300,
        320,
        240,
        padFraction: 0.2,
      );
      expect(side, lessThanOrEqualTo(240));
      expect(x + side, lessThanOrEqualTo(320));
      expect(y + side, lessThanOrEqualTo(240));
    });
  });
}
