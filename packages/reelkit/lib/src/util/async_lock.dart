import 'dart:async';

/// Runs asynchronous actions one at a time, in the order they were queued.
///
/// Used to serialize commands per controller (so `play`, `pause` and `dispose`
/// issued in quick succession reach the engine in order) and pool mutations
/// (so concurrent acquisitions can never exceed the player limit).
class AsyncLock {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  /// Whether an action is running or queued.
  bool get isLocked => _pending > 0;

  /// Queues [action] and completes with its result once it ran.
  Future<T> synchronized<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    _pending++;
    return previous.then((_) => action()).whenComplete(() {
      _pending--;
      done.complete();
    });
  }
}
