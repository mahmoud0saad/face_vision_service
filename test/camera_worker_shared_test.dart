import 'dart:async';

import 'package:face_vision_service/src/async_lock.dart';
import 'package:face_vision_service/src/camera_isolate_worker.dart';
import 'package:face_vision_service/src/opencv_camera_datasource.dart';
import 'package:test/test.dart';

void main() {
  group('shared camera worker', () {
    test('every datasource resolves to the single shared worker', () {
      final a = OpenCvCameraDatasource();
      final b = OpenCvCameraDatasource();

      // Both must route to the same process-wide isolate worker so reopening
      // the device never spawns a competing isolate.
      expect(CameraIsolateWorker.shared, same(CameraIsolateWorker.shared));
      expect(a, isNot(same(b)));
    });
  });

  group('AsyncLock', () {
    test('runs sections one at a time in call order', () async {
      final lock = AsyncLock();
      final events = <String>[];

      final first = lock.synchronized(() async {
        events.add('a-start');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        events.add('a-end');
      });

      // Queued while the first section is still running.
      final second = lock.synchronized(() async {
        events.add('b-start');
        events.add('b-end');
      });

      await Future.wait([first, second]);

      expect(events, ['a-start', 'a-end', 'b-start', 'b-end']);
    });

    test('second section does not start until the first releases', () async {
      final lock = AsyncLock();
      final firstStarted = Completer<void>();
      final allowFirstToFinish = Completer<void>();
      var secondStarted = false;

      final first = lock.synchronized(() async {
        firstStarted.complete();
        await allowFirstToFinish.future;
      });

      final second = lock.synchronized(() async {
        secondStarted = true;
      });

      await firstStarted.future;
      // First is holding the lock and has not been allowed to finish yet.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(secondStarted, isFalse);

      allowFirstToFinish.complete();
      await Future.wait([first, second]);
      expect(secondStarted, isTrue);
    });

    test('releases the lock even when a section throws', () async {
      final lock = AsyncLock();

      await expectLater(
        lock.synchronized(() async => throw StateError('boom')),
        throwsStateError,
      );

      // The lock must not be stuck after a failure.
      final result = await lock.synchronized(() async => 42);
      expect(result, 42);
    });
  });
}
