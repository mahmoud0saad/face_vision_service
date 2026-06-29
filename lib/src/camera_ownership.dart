/// Tracks which session currently owns the shared camera device.
///
/// The camera worker is a process-wide singleton, so a superseded session's
/// late `close()`/`grab()` must not release the device or steal frames from the
/// session that is currently running. Each [acquire] hands out a new token; only
/// the latest token may grab or release the device.
class CameraOwnership {
  int _counter = 0;
  int _active = 0;
  bool _deviceOpen = false;

  /// Claims ownership for a new session and marks the device as open.
  int acquire() {
    _active = ++_counter;
    _deviceOpen = true;
    return _active;
  }

  /// True only for the current owner while the device is open.
  bool canGrab(int token) => token == _active && _deviceOpen;

  /// True if [token] is the current owner.
  bool owns(int token) => token == _active;

  /// Attempts to release the device for [token].
  ///
  /// Returns false (and does nothing) for a stale token so a superseded session
  /// cannot free the device out from under the active one. Returns true when the
  /// current owner releases, after which the device is considered closed.
  bool release(int token) {
    if (token != _active) return false;
    _deviceOpen = false;
    return true;
  }

  /// Clears all ownership state (used on full worker teardown).
  void reset() {
    _active = 0;
    _deviceOpen = false;
  }
}
