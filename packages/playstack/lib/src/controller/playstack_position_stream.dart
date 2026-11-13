import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// Builds a position stream that polls the engine only while it has a
/// listener, and only while playing or right after a state change or seek.
///
/// A paused video therefore costs no channel traffic.
@internal
Stream<PlayStackPositionSnapshot> pollPositions({
  required Duration interval,
  required Future<PlayStackPositionSnapshot> Function() read,
  required bool Function() isPlaying,
  required bool Function() isClosed,
  required Listenable changes,
  required void Function(StreamController<PlayStackPositionSnapshot>) register,
  required void Function(StreamController<PlayStackPositionSnapshot>)
  unregister,
}) {
  // Closed when the listener cancels, or by the owner when it is disposed.
  // ignore: close_sinks
  late final StreamController<PlayStackPositionSnapshot> controller;
  Timer? timer;
  PlayStackPositionSnapshot? last;
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
    } on PlayStackException {
      // Transient (player reassigned or disposed); the next tick retries.
    } finally {
      busy = false;
    }
  }

  void onChange() => unawaited(poll());

  controller = StreamController<PlayStackPositionSnapshot>(
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
