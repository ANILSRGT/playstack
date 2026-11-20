import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';
import '../feed/playstack_feed_manager.dart';

/// Pauses playback after a while or at the end of the current video, for
/// users who fall asleep watching or listening.
///
/// ```dart
/// final timer = manager.sleepTimer; // or view.manager!.sleepTimer
/// timer.start(const Duration(minutes: 30));
/// timer.startEndOfVideo();
/// timer.cancel();
/// ```
///
/// When it ends, every video of the manager pauses and its feeds stop
/// moving to the next video, until the user plays again. The sound fades out
/// over the last seconds first. It notifies its listeners every second while
/// it runs, so a menu can show [remaining].
class PlayStackSleepTimer extends ChangeNotifier {
  /// Created by `PlayStackManager`.
  @internal
  PlayStackSleepTimer({
    required this._controllers,
    required this._feeds,
    required this._active,
  });

  final List<PlayStackPlayerController> Function() _controllers;
  final List<PlayStackFeedManager> Function() _feeds;
  final ValueListenable<PlayStackPlayerController?> _active;

  Timer? _timer;
  Duration? _left;
  Duration _fadeOut = Duration.zero;
  bool _endOfVideo = false;
  PlayStackPlayerController? _watched;
  final Map<PlayStackPlayerController, double> _volumes =
      <PlayStackPlayerController, double>{};
  final Set<PlayStackFeedManager> _pausedFeeds = <PlayStackFeedManager>{};
  final StreamController<void> _finished = StreamController<void>.broadcast();
  bool _disposed = false;

  static const Duration _step = Duration(seconds: 1);

  /// Whether a timer runs ([start] or [startEndOfVideo]).
  bool get isActive => _left != null || _endOfVideo;

  /// Whether the timer waits for the end of the current video.
  bool get isEndOfVideo => _endOfVideo;

  /// Time left, or null when no timed sleep runs.
  Duration? get remaining => _left;

  /// Fires each time the timer pauses playback.
  Stream<void> get onFinished => _finished.stream;

  /// Pauses everything after [after] of playback. The sound fades out over
  /// the last [fadeOut] (10 seconds by default; [Duration.zero] stops at
  /// once). Replaces a running timer.
  void start(Duration after, {Duration fadeOut = const Duration(seconds: 10)}) {
    _clear();
    _resumeFeeds();
    _left = after;
    _fadeOut = fadeOut;
    _timer = Timer.periodic(_step, (_) => _tick());
    notifyListeners();
  }

  /// Pauses when the video playing now (or the next one started before it
  /// ends) reaches its end. Replaces a running timer.
  void startEndOfVideo() {
    _clear();
    _resumeFeeds();
    _endOfVideo = true;
    _active.addListener(_onActive);
    _onActive();
    notifyListeners();
  }

  /// Stops the timer without pausing.
  void cancel() {
    if (!isActive) return;
    _clear();
    notifyListeners();
  }

  /// Adds time to a timed sleep, for example "+5 min".
  void extend(Duration extra) {
    final left = _left;
    if (left == null) return;
    _restoreVolumes();
    _left = left + extra;
    notifyListeners();
  }

  void _onActive() {
    final active = _active.value;
    if (active == null || identical(active, _watched)) return;
    _unwatch();
    _watched = active..addListener(_onWatchedState);
  }

  void _onWatchedState() {
    final watched = _watched;
    if (watched == null) return;
    if (watched.value.status == PlayStackPlaybackStatus.completed) _sleep();
  }

  void _unwatch() {
    final watched = _watched;
    _watched = null;
    if (watched != null && !watched.isDisposed) {
      watched.removeListener(_onWatchedState);
    }
  }

  void _tick() {
    final current = _left;
    if (current == null) return;
    // Counts only while something plays.
    final playing = _controllers().any((c) => c.value.isPlaying);
    final left = playing ? current - _step : current;
    _left = left.isNegative ? Duration.zero : left;
    if (left <= Duration.zero) {
      _sleep();
      return;
    }
    if (_fadeOut > Duration.zero && left <= _fadeOut) {
      final factor = left.inMilliseconds / _fadeOut.inMilliseconds;
      for (final controller in _controllers()) {
        if (!controller.value.isPlaying) continue;
        final original = _volumes[controller] ??= controller.value.volume;
        unawaited(
          controller.setVolume(original * factor).catchError((Object _) {}),
        );
      }
    }
    notifyListeners();
  }

  void _sleep() {
    // Feeds first: none moves on to the next video while it pauses.
    for (final feed in _feeds()) {
      if (feed.isDisposed || feed.isPaused) continue;
      feed.pause();
      _pausedFeeds.add(feed);
    }
    for (final controller in _controllers()) {
      if (controller.value.isPlaying || controller.wantsPlayback) {
        unawaited(controller.pause().catchError((Object _) {}));
      }
    }
    _clear();
    // The next play by the user lets the feeds move on again.
    _active.addListener(_onWake);
    if (!_disposed) {
      _finished.add(null);
      notifyListeners();
    }
  }

  void _onWake() {
    if (_active.value == null) return;
    _resumeFeeds();
  }

  void _resumeFeeds() {
    _active.removeListener(_onWake);
    for (final feed in _pausedFeeds) {
      if (!feed.isDisposed && feed.isPaused) feed.resume();
    }
    _pausedFeeds.clear();
  }

  void _restoreVolumes() {
    for (final MapEntry(key: controller, value: volume) in _volumes.entries) {
      if (controller.isDisposed) continue;
      unawaited(controller.setVolume(volume).catchError((Object _) {}));
    }
    _volumes.clear();
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    _left = null;
    _restoreVolumes();
    if (_endOfVideo) _active.removeListener(_onActive);
    _endOfVideo = false;
    _unwatch();
  }

  @override
  void dispose() {
    _disposed = true;
    _clear();
    _active.removeListener(_onWake);
    unawaited(_finished.close());
    super.dispose();
  }
}
