import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controller/playstack_player_controller.dart';

/// Decides which controllers of a manager may play and tracks the active one.
///
/// With exclusive playback, the most recent `play` request wins: every other
/// controller that plays or is about to play is asked to yield, and a queued
/// `play` that has been superseded does not start playback. Ordering is
/// decided when `play` is called, not when the queued command runs, so a
/// slow preparation cannot override a later request.
@internal
class PlayStackPlaybackCoordinator {
  PlayStackPlaybackCoordinator({required this.exclusive});

  final bool exclusive;

  final ValueNotifier<PlayStackPlayerController?> _active =
      ValueNotifier<PlayStackPlayerController?>(null);

  /// Playing controllers, oldest first.
  final List<PlayStackPlayerController> _playing =
      <PlayStackPlayerController>[];

  PlayStackPlayerController? _latestRequest;

  /// The playing controller that started most recently, or null.
  ValueListenable<PlayStackPlayerController?> get active => _active;

  /// Called synchronously by `play`, before the command is queued.
  void playRequested(
    PlayStackPlayerController controller,
    Iterable<PlayStackPlayerController> all,
  ) {
    if (!exclusive) return;
    _latestRequest = controller;
    for (final other in List<PlayStackPlayerController>.of(all)) {
      if (identical(other, controller) || !other.wantsPlayback) continue;
      unawaited(other.yieldPlayback().catchError(_reportError));
    }
  }

  /// Whether [controller] may start playback now.
  bool mayStartPlayback(PlayStackPlayerController controller) {
    if (!exclusive) return true;
    final latest = _latestRequest;
    return latest == null || identical(latest, controller);
  }

  void playingChanged(PlayStackPlayerController controller, bool isPlaying) {
    _playing.remove(controller);
    if (isPlaying) _playing.add(controller);
    _active.value = _playing.isEmpty ? null : _playing.last;
  }

  void controllerDisposed(PlayStackPlayerController controller) {
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
        library: 'playstack',
        context: ErrorDescription('while pausing for exclusive playback'),
      ),
    );
  }
}
