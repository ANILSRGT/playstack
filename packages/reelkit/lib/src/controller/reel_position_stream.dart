import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// Builds a position stream that polls the engine only while it has a
/// listener, and only while playing or right after a state change or seek.
///
/// A paused video therefore costs no channel traffic.
@internal
Stream<ReelPositionSnapshot> pollPositions({
  required Duration interval,
  required Future<ReelPositionSnapshot> Function() read,
  required bool Function() isPlaying,
  required bool Function() isClosed,
  required Listenable changes,
  required void Function(StreamController<ReelPositionSnapshot>) register,
  required void Function(StreamController<ReelPositionSnapshot>) unregister,
}) {
  // Closed when the listener cancels, or by the owner when it is disposed.
  // ignore: close_sinks
  late final StreamController<ReelPositionSnapshot> controller;
  Timer? timer;
  ReelPositionSnapshot? last;
  var busy = false;

  Future<void> poll() async {
    if (busy || isClosed() || controller.isClosed) return;
    busy = true;
    try {
      final snapshot = await read();
      if (!controller.isClosed && snapshot != last) {
        last = snapshot;
        controller.add(snapshot);
      }
    } on ReelKitException {
      // Transient (player reassigned or disposed); the next tick retries.
    } finally {
      busy = false;
    }
  }

  void onChange() => unawaited(poll());

  controller = StreamController<ReelPositionSnapshot>(
    onListen: () {
      changes.addListener(onChange);
      unawaited(poll());
      timer = Timer.periodic(interval, (_) {
        if (isPlaying()) unawaited(poll());
      });
    },
    onCancel: () {
      timer?.cancel();
      changes.removeListener(onChange);
      unregister(controller);
      // Single-subscription: it can never be listened to again. Not
      // awaited: close() itself waits for this onCancel to finish.
      unawaited(controller.close());
    },
  );
  register(controller);
  return controller.stream;
}
