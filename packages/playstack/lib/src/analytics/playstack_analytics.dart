import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';

/// Which analytics events PlayStack reports, and how often it checks the
/// position for [PlayStackProgressEvent]s.
@immutable
class PlayStackAnalyticsConfig {
  /// Creates an analytics configuration. The defaults suit most apps.
  const PlayStackAnalyticsConfig({
    this.enabled = true,
    this.progressMilestones = const [25, 50, 75],
    this.positionInterval = const Duration(seconds: 1),
  });

  /// No events at all.
  static const PlayStackAnalyticsConfig disabled = PlayStackAnalyticsConfig(
    enabled: false,
  );

  /// Whether events are reported. True by default; events cost nothing while
  /// nobody listens to them.
  final bool enabled;

  /// The percentages of a video that report a [PlayStackProgressEvent] the
  /// first time playback passes them: 25, 50 and 75 by default. The end of
  /// the video reports a [PlayStackCompleteEvent] instead of 100.
  final List<int> progressMilestones;

  /// How often the position is read while a video plays, for the
  /// milestones. 1 second by default.
  final Duration positionInterval;

  @override
  bool operator ==(Object other) =>
      other is PlayStackAnalyticsConfig &&
      other.enabled == enabled &&
      listEquals(other.progressMilestones, progressMilestones) &&
      other.positionInterval == positionInterval;

  @override
  int get hashCode => Object.hash(
    enabled,
    Object.hashAll(progressMilestones),
    positionInterval,
  );
}

/// Something that happened to a video, for your analytics: started, paused,
/// reached half, rebuffered, failed.
///
/// Listen to `PlayStackManager.analytics` for the videos of one manager, or
/// to [PlayStackAnalytics.all] for every video of the app (also the ones of
/// a `PlayStackFeedView` that created its own manager). [name] and
/// [parameters] are ready for Firebase, Mixpanel, Amplitude or your backend:
///
/// ```dart
/// PlayStackAnalytics.all.listen((event) {
///   FirebaseAnalytics.instance.logEvent(
///     name: event.name,
///     parameters: event.parameters,
///   );
/// });
/// ```
///
/// Or switch on the event type:
///
/// ```dart
/// PlayStackAnalytics.all.listen((event) {
///   switch (event) {
///     case PlayStackStartEvent(:final startupTime):
///       metrics.recordStartup(startupTime);
///     case PlayStackRebufferEvent(:final stall):
///       metrics.recordStall(stall);
///     default:
///   }
/// });
/// ```
@immutable
sealed class PlayStackAnalyticsEvent {
  const PlayStackAnalyticsEvent._({
    required this.controller,
    required this.source,
    required this.contentId,
    required this.position,
    required this.duration,
    required this.time,
  });

  /// The controller of the video.
  final PlayStackPlayerController controller;

  /// The video.
  final PlayStackSource source;

  /// Your id of the video ([PlayStackPlayerController.contentId]). Feeds set
  /// it to the item id.
  final String? contentId;

  /// Where playback was when the event happened.
  final Duration position;

  /// The length of the video, when known.
  final Duration? duration;

  /// When the event happened.
  final DateTime time;

  /// A snake_case name for analytics services, such as `video_start`.
  String get name;

  /// The event as flat key-value pairs (strings and numbers), for analytics
  /// services. Durations are in milliseconds.
  Map<String, Object> get parameters => {
    'content_id': ?contentId,
    'source': _describe(source),
    'position_ms': position.inMilliseconds,
    if (duration case final duration?) 'duration_ms': duration.inMilliseconds,
    ..._details,
  };

  Map<String, Object> get _details => const {};

  static String _describe(PlayStackSource source) => switch (source) {
    PlayStackNetworkSource(:final url) => url,
    _ => source.description,
  };

  @override
  String toString() => '$runtimeType($parameters)';
}

/// The video started loading: a new video, or the same one again after it
/// lost its player.
final class PlayStackLoadEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackLoadEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
  }) : super._();

  @override
  String get name => 'video_load';
}

/// The video started playing for the first time since it was loaded.
final class PlayStackStartEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackStartEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
    required this.startupTime,
  }) : super._();

  /// From the start of loading to the first moment of playback: how long
  /// the user waited.
  final Duration startupTime;

  @override
  String get name => 'video_start';

  @override
  Map<String, Object> get _details => {
    'startup_ms': startupTime.inMilliseconds,
  };
}

/// Playback paused, by the user or the app.
final class PlayStackPauseEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackPauseEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
  }) : super._();

  @override
  String get name => 'video_pause';
}

/// Playback continued after a pause.
final class PlayStackResumeEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackResumeEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
  }) : super._();

  @override
  String get name => 'video_resume';
}

/// The video moved from [from] to [position] by a seek.
final class PlayStackSeekEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackSeekEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
    required this.from,
  }) : super._();

  /// Where playback was before the seek.
  final Duration from;

  @override
  String get name => 'video_seek';

  @override
  Map<String, Object> get _details => {'from_ms': from.inMilliseconds};
}

/// Playback passed [percent] of the video for the first time. See
/// [PlayStackAnalyticsConfig.progressMilestones].
final class PlayStackProgressEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackProgressEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
    required this.percent,
  }) : super._();

  /// The milestone, for example 25.
  final int percent;

  @override
  String get name => 'video_progress';

  @override
  Map<String, Object> get _details => {'percent': percent};
}

/// The video played to its end. A looping video reports this every time it
/// starts over.
final class PlayStackCompleteEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackCompleteEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
  }) : super._();

  @override
  String get name => 'video_complete';
}

/// Playback stalled for [duration] while the video loaded more data. Reported
/// when it plays again.
final class PlayStackRebufferEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackRebufferEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
    required this.stall,
    required this.afterSeek,
  }) : super._();

  /// How long playback stalled.
  final Duration stall;

  /// Whether the stall followed a seek, which is expected, rather than a
  /// slow network.
  final bool afterSeek;

  @override
  String get name => 'video_rebuffer';

  @override
  Map<String, Object> get _details => {
    'stall_ms': stall.inMilliseconds,
    'after_seek': afterSeek ? 1 : 0,
  };
}

/// The picture size changed: adaptive streaming moved to another rendition,
/// or the user picked a quality.
final class PlayStackQualityEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackQualityEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
    required this.width,
    required this.height,
    required this.chosenByUser,
  }) : super._();

  /// The new picture width in pixels.
  final int width;

  /// The new picture height in pixels.
  final int height;

  /// Whether the user picked a quality
  /// ([PlayStackPlayerController.setVideoQuality]); false for an automatic
  /// switch.
  final bool chosenByUser;

  @override
  String get name => 'video_quality';

  @override
  Map<String, Object> get _details => {
    'width': width,
    'height': height,
    'by_user': chosenByUser ? 1 : 0,
  };
}

/// The video failed.
final class PlayStackFailureEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackFailureEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
    required this.error,
  }) : super._();

  /// What went wrong.
  final PlayStackException error;

  @override
  String get name => 'video_error';

  @override
  Map<String, Object> get _details => {
    'error_code': error.code.name,
    'error_message': error.message,
  };
}

/// The user is done with the video: another video replaced it, or its
/// controller was released or disposed (in a feed: the user swiped far
/// away). Carries the totals of the visit.
final class PlayStackEndEvent extends PlayStackAnalyticsEvent {
  /// Created by PlayStack.
  const PlayStackEndEvent({
    required super.controller,
    required super.source,
    required super.contentId,
    required super.position,
    required super.duration,
    required super.time,
    required this.watchTime,
    required this.stallTime,
    required this.stalls,
    required this.completed,
    required this.furthest,
  }) : super._();

  /// How long the video played (not counting pauses and stalls).
  final Duration watchTime;

  /// How long playback stalled in total.
  final Duration stallTime;

  /// How many times playback stalled.
  final int stalls;

  /// Whether the video played to its end at least once.
  final bool completed;

  /// The furthest position playback reached.
  final Duration furthest;

  @override
  String get name => 'video_end';

  @override
  Map<String, Object> get _details => {
    'watch_ms': watchTime.inMilliseconds,
    'stall_ms': stallTime.inMilliseconds,
    'stalls': stalls,
    'completed': completed ? 1 : 0,
    'furthest_ms': furthest.inMilliseconds,
  };
}

/// The analytics events of one manager's videos, and of the whole app
/// through [all]. See [PlayStackAnalyticsEvent].
class PlayStackAnalytics {
  /// Created by `PlayStackManager`.
  @internal
  PlayStackAnalytics(this.config);

  static final StreamController<PlayStackAnalyticsEvent> _all =
      StreamController<PlayStackAnalyticsEvent>.broadcast(sync: true);

  /// The events of every video in the app, from every manager. Listen once,
  /// for example in `main`.
  static Stream<PlayStackAnalyticsEvent> get all => _all.stream;

  /// The settings: milestones and whether events are reported at all.
  final PlayStackAnalyticsConfig config;

  final StreamController<PlayStackAnalyticsEvent> _events =
      StreamController<PlayStackAnalyticsEvent>.broadcast(sync: true);

  /// The events of this manager's videos.
  Stream<PlayStackAnalyticsEvent> get events => _events.stream;

  /// Whether anyone listens, so events are worth producing.
  bool get _wanted =>
      config.enabled && (_events.hasListener || _all.hasListener);

  /// Starts following [controller]. Called by the controller.
  @internal
  PlayStackAnalyticsTracker track(PlayStackPlayerController controller) =>
      PlayStackAnalyticsTracker._(this, controller);

  void _emit(PlayStackAnalyticsEvent event) {
    if (!config.enabled) return;
    if (_events.hasListener) _events.add(event);
    if (_all.hasListener) _all.add(event);
  }

  /// Stops reporting. Called by `PlayStackManager.dispose`.
  @internal
  void dispose() => unawaited(_events.close());
}

/// Follows one controller and turns its state changes into events.
@internal
class PlayStackAnalyticsTracker {
  PlayStackAnalyticsTracker._(this._analytics, this._controller) {
    _controller.addListener(_onState);
    _controller.videoQuality.addListener(_onQualityChosen);
    _state = _controller.value;
    _source = _controller.source;
  }

  final PlayStackAnalytics _analytics;
  final PlayStackPlayerController _controller;

  late PlayStackPlaybackState _state;
  late PlayStackSource _source;

  // One visit: from loading a source until it is replaced or released.
  bool _inVisit = false;
  bool _started = false;
  bool _completed = false;
  final Stopwatch _sinceLoad = Stopwatch();
  final Stopwatch _watch = Stopwatch();
  final Stopwatch _stall = Stopwatch();
  Duration _stallTotal = Duration.zero;
  int _stalls = 0;
  DateTime? _lastSeek;
  Duration _position = Duration.zero;
  Duration _furthest = Duration.zero;
  final Set<int> _reached = <int>{};
  Timer? _ticker;
  bool _userChoseQuality = false;
  int? _width;
  int? _height;
  bool _closed = false;

  bool get wanted => !_closed && _analytics._wanted;

  /// Called by the controller before it seeks.
  void seeking(Duration from, Duration to) {
    if (!wanted || !_inVisit) return;
    _lastSeek = DateTime.now();
    _position = to;
    _emit(
      (c, s, id, d, t) => PlayStackSeekEvent(
        controller: c,
        source: s,
        contentId: id,
        position: to,
        duration: d,
        time: t,
        from: from,
      ),
    );
  }

  /// Called by the controller when it releases its player, changes source
  /// or is disposed.
  void endVisit() {
    if (!_inVisit) return;
    _inVisit = false;
    _ticker?.cancel();
    _ticker = null;
    _watch.stop();
    _closeStall(emit: false);
    if (wanted) {
      _emit(
        (c, s, id, d, t) => PlayStackEndEvent(
          controller: c,
          source: s,
          contentId: id,
          position: _position,
          duration: d,
          time: t,
          watchTime: _watch.elapsed,
          stallTime: _stallTotal,
          stalls: _stalls,
          completed: _completed,
          furthest: _furthest,
        ),
      );
    }
  }

  void dispose() {
    endVisit();
    _closed = true;
    _controller.removeListener(_onState);
    _controller.videoQuality.removeListener(_onQualityChosen);
  }

  void _beginVisit() {
    _inVisit = true;
    _started = false;
    _completed = false;
    _sinceLoad
      ..reset()
      ..start();
    _watch.reset();
    _stall.reset();
    _stallTotal = Duration.zero;
    _stalls = 0;
    _lastSeek = null;
    _position = _controller.startPosition ?? Duration.zero;
    _furthest = _position;
    _reached.clear();
    _width = null;
    _height = null;
    _userChoseQuality = false;
    if (wanted) {
      _emit(
        (c, s, id, d, t) => PlayStackLoadEvent(
          controller: c,
          source: s,
          contentId: id,
          position: _position,
          duration: d,
          time: t,
        ),
      );
    }
  }

  void _onState() {
    if (_closed) return;
    final previous = _state;
    final next = _state = _controller.value;
    if (!identical(_controller.source, _source)) {
      endVisit();
      _source = _controller.source;
    }
    if (next.status == PlayStackPlaybackStatus.initializing &&
        previous.status != PlayStackPlaybackStatus.initializing &&
        !_inVisit) {
      _beginVisit();
    }
    if (!_inVisit) return;

    if (next.isPlaying != previous.isPlaying) {
      if (next.isPlaying) {
        _watch.start();
        _startTicker();
        if (!_started) {
          _started = true;
          _sinceLoad.stop();
          if (wanted) {
            _emit(
              (c, s, id, d, t) => PlayStackStartEvent(
                controller: c,
                source: s,
                contentId: id,
                position: _position,
                duration: d,
                time: t,
                startupTime: _sinceLoad.elapsed,
              ),
            );
          }
        } else if (previous.status == PlayStackPlaybackStatus.paused &&
            wanted) {
          _emit(
            (c, s, id, d, t) => PlayStackResumeEvent(
              controller: c,
              source: s,
              contentId: id,
              position: _position,
              duration: d,
              time: t,
            ),
          );
        }
      } else {
        _watch.stop();
        _ticker?.cancel();
        _ticker = null;
        if (next.status == PlayStackPlaybackStatus.paused && wanted) {
          unawaited(
            _readPosition().then((_) {
              _emit(
                (c, s, id, d, t) => PlayStackPauseEvent(
                  controller: c,
                  source: s,
                  contentId: id,
                  position: _position,
                  duration: d,
                  time: t,
                ),
              );
            }),
          );
        }
      }
    }

    // Stalls: buffering after playback started, while the user wants it to
    // play.
    final stalled =
        _started &&
        next.isBuffering &&
        (next.status == PlayStackPlaybackStatus.playing ||
            next.status == PlayStackPlaybackStatus.paused &&
                _controller.wantsPlayback);
    if (stalled && !_stall.isRunning) {
      _stall
        ..reset()
        ..start();
    } else if (!next.isBuffering && _stall.isRunning) {
      _closeStall(emit: true);
    }

    if (next.status == PlayStackPlaybackStatus.completed &&
        previous.status != PlayStackPlaybackStatus.completed) {
      _complete();
    }

    final info = next.videoInfo;
    if (info != null &&
        info.width > 0 &&
        info.height > 0 &&
        (info.width != _width || info.height != _height)) {
      final first = _width == null;
      _width = info.width;
      _height = info.height;
      if (!first && wanted) {
        final byUser = _userChoseQuality;
        _userChoseQuality = false;
        _emit(
          (c, s, id, d, t) => PlayStackQualityEvent(
            controller: c,
            source: s,
            contentId: id,
            position: _position,
            duration: d,
            time: t,
            width: info.width,
            height: info.height,
            chosenByUser: byUser,
          ),
        );
      }
    }

    final error = next.error;
    if (next.hasError &&
        error != null &&
        !identical(error, previous.error) &&
        wanted) {
      _emit(
        (c, s, id, d, t) => PlayStackFailureEvent(
          controller: c,
          source: s,
          contentId: id,
          position: _position,
          duration: d,
          time: t,
          error: error,
        ),
      );
    }
  }

  void _onQualityChosen() => _userChoseQuality = true;

  void _closeStall({required bool emit}) {
    if (!_stall.isRunning) return;
    _stall.stop();
    final stall = _stall.elapsed;
    _stallTotal += stall;
    _stalls++;
    final seek = _lastSeek;
    final afterSeek =
        seek != null &&
        DateTime.now().difference(seek) < const Duration(seconds: 3) + stall;
    if (emit && wanted) {
      _emit(
        (c, s, id, d, t) => PlayStackRebufferEvent(
          controller: c,
          source: s,
          contentId: id,
          position: _position,
          duration: d,
          time: t,
          stall: stall,
          afterSeek: afterSeek,
        ),
      );
    }
  }

  void _complete() {
    _completed = true;
    final duration = _state.duration;
    if (duration != null) {
      _position = duration;
      if (duration > _furthest) _furthest = duration;
    }
    _reachMilestones();
    if (wanted) {
      _emit(
        (c, s, id, d, t) => PlayStackCompleteEvent(
          controller: c,
          source: s,
          contentId: id,
          position: _position,
          duration: d,
          time: t,
        ),
      );
    }
    // A looping video starts over: its milestones count again.
    _reached.clear();
  }

  void _startTicker() {
    _ticker?.cancel();
    if (!wanted) return;
    _ticker = Timer.periodic(
      _analytics.config.positionInterval,
      (_) => unawaited(_tick()),
    );
  }

  Future<void> _tick() async {
    if (!wanted || !_inVisit) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    final before = _position;
    await _readPosition();
    final duration = _state.duration;
    // A looping video jumped from the end to the beginning.
    if (_state.isLooping &&
        duration != null &&
        before > duration * 0.9 &&
        _position < duration * 0.1) {
      _complete();
      return;
    }
    _reachMilestones();
  }

  Future<void> _readPosition() async {
    try {
      final position = (await _controller.getPosition()).position;
      _position = position;
      if (position > _furthest) _furthest = position;
    } on Object {
      // Disposed or between players; keep the last known position.
    }
  }

  void _reachMilestones() {
    final duration = _state.duration;
    if (duration == null || duration <= Duration.zero || !wanted) return;
    if (_state.videoInfo?.isLive ?? false) return;
    final percent = _position.inMilliseconds * 100 / duration.inMilliseconds;
    for (final milestone in _analytics.config.progressMilestones) {
      if (percent < milestone || _reached.contains(milestone)) continue;
      _reached.add(milestone);
      _emit(
        (c, s, id, d, t) => PlayStackProgressEvent(
          controller: c,
          source: s,
          contentId: id,
          position: _position,
          duration: d,
          time: t,
          percent: milestone,
        ),
      );
    }
  }

  void _emit(
    PlayStackAnalyticsEvent Function(
      PlayStackPlayerController controller,
      PlayStackSource source,
      String? contentId,
      Duration? duration,
      DateTime time,
    )
    create,
  ) {
    _analytics._emit(
      create(
        _controller,
        _source,
        _controller.contentId,
        _state.duration,
        DateTime.now(),
      ),
    );
  }
}
