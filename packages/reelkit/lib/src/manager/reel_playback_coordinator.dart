import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controller/reel_player_controller.dart';

/// Decides which controllers of a manager may play and tracks the active one.
///
/// With exclusive playback, the most recent `play` request wins: every other
/// controller that plays or is about to play is asked to yield, and a queued
/// `play` that has been superseded does not start playback. Ordering is
/// decided when `play` is called, not when the queued command runs, so a
/// slow preparation cannot override a later request.
@internal
class ReelPlaybackCoordinator {
  ReelPlaybackCoordinator({required this.exclusive});

  final bool exclusive;

  final ValueNotifier<ReelPlayerController?> _active =
      ValueNotifier<ReelPlayerController?>(null);

  /// Playing controllers, oldest first.
  final List<ReelPlayerController> _playing = <ReelPlayerController>[];

  ReelPlayerController? _latestRequest;

  /// The playing controller that started most recently, or null.
  ValueListenable<ReelPlayerController?> get active => _active;

  /// Called synchronously by `play`, before the command is queued.
  void playRequested(
    ReelPlayerController controller,
    Iterable<ReelPlayerController> all,
  ) {
    if (!exclusive) return;
    _latestRequest = controller;
    for (final other in List<ReelPlayerController>.of(all)) {
      if (identical(other, controller) || !other.wantsPlayback) continue;
      unawaited(other.yieldPlayback().catchError(_reportError));
    }
  }

  /// Whether [controller] may start playback now.
  bool mayStartPlayback(ReelPlayerController controller) {
    if (!exclusive) return true;
    final latest = _latestRequest;
    return latest == null || identical(latest, controller);
  }

  void playingChanged(ReelPlayerController controller, bool isPlaying) {
    _playing.remove(controller);
    if (isPlaying) _playing.add(controller);
    _active.value = _playing.isEmpty ? null : _playing.last;
  }

  void controllerDisposed(ReelPlayerController controller) {
    if (identical(_latestRequest, controller)) _latestRequest = null;
    playingChanged(controller, false);
  }

  void dispose() {
    _playing.clear();
    _latestRequest = null;
    _active.dispose();
  }

  void _reportError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'reelkit',
        context: ErrorDescription('while pausing for exclusive playback'),
      ),
    );
  }
}
