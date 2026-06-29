import 'package:face_vision_service/src/camera_ownership.dart';
import 'package:test/test.dart';

void main() {
  group('CameraOwnership', () {
    test('acquire hands out increasing tokens and opens the device', () {
      final ownership = CameraOwnership();

      final first = ownership.acquire();
      final second = ownership.acquire();

      expect(second, greaterThan(first));
      expect(ownership.owns(second), isTrue);
      expect(ownership.canGrab(second), isTrue);
    });

    test('an older token cannot grab once a newer one is acquired', () {
      final ownership = CameraOwnership();

      final stale = ownership.acquire();
      final current = ownership.acquire();

      expect(ownership.canGrab(stale), isFalse);
      expect(ownership.canGrab(current), isTrue);
    });

    test('release(staleToken) is ignored and leaves the device open', () {
      final ownership = CameraOwnership();

      final stale = ownership.acquire();
      final current = ownership.acquire();

      expect(ownership.release(stale), isFalse);
      // The current owner must still be able to grab.
      expect(ownership.canGrab(current), isTrue);
    });

    test('release(currentToken) closes the device', () {
      final ownership = CameraOwnership();

      final token = ownership.acquire();

      expect(ownership.release(token), isTrue);
      expect(ownership.canGrab(token), isFalse);
    });

    test('reset clears ownership', () {
      final ownership = CameraOwnership();
      final token = ownership.acquire();

      ownership.reset();

      expect(ownership.canGrab(token), isFalse);
      expect(ownership.owns(token), isFalse);
    });
  });
}
