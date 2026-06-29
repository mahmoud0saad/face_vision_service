import 'dart:async';

/// Minimal async mutex that serializes [synchronized] sections in call order.
///
/// Each call to [synchronized] runs only after every previously queued section
/// has completed, so overlapping camera commands (open / release / dispose)
/// never interleave on the shared worker isolate.
class AsyncLock {
  Future<void> _last = Future<void>.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _last;
    _last = completer.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        completer.complete();
      }
    });
  }
}
