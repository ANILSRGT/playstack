import 'dart:async';

/// Runs asynchronous actions one at a time, in the order they were queued.
///
/// Used to serialize commands per controller (so `play`, `pause` and `dispose`
/// issued in quick succession reach the engine in order) and pool mutations
/// (so concurrent acquisitions can never exceed the player limit).
class AsyncLock {
  /// Completes when the last queued action finished; null while idle.
  ///
  /// Keeping no future while idle matters beyond saving a microtask: a
  /// completed future schedules its listeners in the zone it was created
  /// in, which may be a test zone that no longer runs.
  Future<void>? _tail;
  int _pending = 0;

  /// Whether an action is running or queued.
  bool get isLocked => _pending > 0;

  /// Queues [action] and completes with its result once it ran.
  Future<T> synchronized<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    final tail = done.future;
    _tail = tail;
    _pending++;
    final run = previous == null
        ? Future<T>.sync(action)
        : previous.then((_) => action());
    return run.whenComplete(() {
      _pending--;
      if (identical(_tail, tail)) _tail = null;
      done.complete();
    });
  }
}
