import 'dart:async';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';
import '../feed_view/playstack_feed_view.dart';
import 'playstack_watch_progress.dart';

/// What a [PlayStackSkipMarker] covers.
enum PlayStackSkipMarkerType {
  /// The opening titles. The button says "Skip intro".
  intro,

  /// A summary of earlier episodes. The button says "Skip recap".
  recap,

  /// The closing credits. With [PlayStackSeries.nextUp] the next episode is
  /// offered here instead of a skip button.
  credits,

  /// Anything else, with your own [PlayStackSkipMarker.label].
  other,
}

/// A part of a video the user may skip: the intro, a recap, the credits.
@immutable
class PlayStackSkipMarker {
  /// Creates a marker from [start] to [end].
  const PlayStackSkipMarker({
    required this.start,
    required this.end,
    this.type = PlayStackSkipMarkerType.other,
    this.label,
  });

  /// The opening titles from [start] to [end].
  const PlayStackSkipMarker.intro({
    required this.start,
    required this.end,
    this.label,
  }) : type = PlayStackSkipMarkerType.intro;

  /// A recap from [start] to [end].
  const PlayStackSkipMarker.recap({
    required this.start,
    required this.end,
    this.label,
  }) : type = PlayStackSkipMarkerType.recap;

  /// The credits from [start] to the end of the video ([end] defaults to
  /// a very large value).
  const PlayStackSkipMarker.credits({
    required this.start,
    this.end = const Duration(days: 1),
    this.label,
  }) : type = PlayStackSkipMarkerType.credits;

  /// Where the part starts.
  final Duration start;

  /// Where it ends; skipping moves here.
  final Duration end;

  /// What the part is.
  final PlayStackSkipMarkerType type;

  /// The button text. Null uses [defaultLabel].
  final String? label;

  /// "Skip intro", "Skip recap", "Skip credits" or "Skip".
  String get defaultLabel => switch (type) {
    PlayStackSkipMarkerType.intro => 'Skip intro',
    PlayStackSkipMarkerType.recap => 'Skip recap',
    PlayStackSkipMarkerType.credits => 'Skip credits',
    PlayStackSkipMarkerType.other => 'Skip',
  };

  /// Whether [position] is inside the part.
  bool contains(Duration position) => position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      other is PlayStackSkipMarker &&
      other.start == start &&
      other.end == end &&
      other.type == type &&
      other.label == label;

  @override
  int get hashCode => Object.hash(start, end, type, label);
}

/// When and how long the next episode is offered before it plays. See
/// [PlayStackSeries.nextUp].
@immutable
class PlayStackNextUp {
  /// Creates a next-episode setting.
  const PlayStackNextUp({
    this.countdown = const Duration(seconds: 5),
    this.showBefore = const Duration(seconds: 10),
    this.atCredits = true,
  });

  /// How long the offer counts down before the next episode plays, 5
  /// seconds by default. [Duration.zero] waits for the user (no automatic
  /// move).
  final Duration countdown;

  /// How long before the end the offer appears, 10 seconds by default.
  final Duration showBefore;

  /// Whether a [PlayStackSkipMarkerType.credits] marker starts the offer
  /// instead of [showBefore]. True by default.
  final bool atCredits;
}

/// What a next-episode offer shows and can do; passed to
/// [PlayStackSeries.nextUpBuilder].
class PlayStackNextUpDetails<T> {
  /// Created by the feed view.
  const PlayStackNextUpDetails({
    required this.next,
    required this.remaining,
    required this.countdown,
    required this.playNow,
    required this.cancel,
  });

  /// The next item.
  final T next;

  /// How long until it plays by itself, or null when it waits for the
  /// user ([PlayStackNextUp.countdown] is zero).
  final Duration? remaining;

  /// The whole countdown.
  final Duration countdown;

  /// Moves to the next item now.
  final VoidCallback playNow;

  /// Hides the offer and stays on this video.
  final VoidCallback cancel;

  /// How much of the countdown has passed, from 0.0 to 1.0.
  double get progress {
    final left = remaining;
    if (left == null || countdown <= Duration.zero) return 0;
    return 1 - (left.inMilliseconds / countdown.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Builds a skip button for [marker]; call [skip] to skip it.
typedef PlayStackSkipButtonBuilder<T> = Widget Function(
  BuildContext context,
  PlayStackFeedPage<T> page,
  PlayStackSkipMarker marker,
  VoidCallback skip,
);

/// Builds the next-episode offer.
typedef PlayStackNextUpBuilder<T> = Widget Function(
  BuildContext context,
  PlayStackFeedPage<T> page,
  PlayStackNextUpDetails<T> details,
);

/// Features for watching a series in a `PlayStackFeedView`: continuing
/// where the user stopped, skip buttons and the next-episode countdown.
/// Every part is optional and replaceable.
///
/// ```dart
/// PlayStackFeedView<Episode>(
///   items: episodes,
///   itemId: (episode) => episode.id,
///   series: PlayStackSeries(
///     progress: watchProgress,                       // continue watching
///     skipMarkers: (episode) => [
///       PlayStackSkipMarker.intro(start: Duration.zero, end: episode.introEnd),
///       PlayStackSkipMarker.credits(start: episode.creditsStart),
///     ],
///     nextUp: const PlayStackNextUp(countdown: Duration(seconds: 5)),
///     nextUpLabel: (episode) => 'Episode ${episode.number}',
///   ),
/// )
/// ```
///
/// The skip button and the offer are drawn by the view above your
/// controls, so they work with your own `controlsBuilder` as well. Replace
/// their look with [skipButtonBuilder] and [nextUpBuilder].
@immutable
class PlayStackSeries<T> {
  /// Creates series options. Without arguments nothing changes but the
  /// next-episode offer.
  const PlayStackSeries({
    this.progress,
    this.skipMarkers,
    this.nextUp = const PlayStackNextUp(),
    this.nextUpLabel,
    this.skipButtonBuilder,
    this.nextUpBuilder,
  });

  /// Saves where the user stopped each item (by `itemId`) and starts it
  /// there next time. Null (the default) saves nothing.
  final PlayStackWatchProgress? progress;

  /// The parts of an item the user may skip. Null (the default) shows no
  /// skip buttons.
  final List<PlayStackSkipMarker> Function(T item)? skipMarkers;

  /// When the next episode is offered near the end. Null turns the offer
  /// off.
  final PlayStackNextUp? nextUp;

  /// The name of the next item on the default offer, such as "Episode 4".
  final String Function(T next)? nextUpLabel;

  /// Replaces the default [PlayStackSkipButton].
  final PlayStackSkipButtonBuilder<T>? skipButtonBuilder;

  /// Replaces the default [PlayStackNextUpCard].
  final PlayStackNextUpBuilder<T>? nextUpBuilder;
}

/// The default skip button: a translucent pill such as "Skip intro".
class PlayStackSkipButton extends StatelessWidget {
  /// Creates a skip button.
  const PlayStackSkipButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFFFFFFFF),
  });

  /// The text, for example "Skip intro".
  final String label;

  /// Called on tap.
  final VoidCallback onPressed;

  /// Text and border color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB3000000),
      shape: StadiumBorder(
        side: BorderSide(color: color.withValues(alpha: 0.7)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.skip_next_rounded, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The default next-episode offer: the next item's name, a countdown bar,
/// "Play now" and a close button.
class PlayStackNextUpCard extends StatelessWidget {
  /// Creates the card.
  const PlayStackNextUpCard({
    super.key,
    required this.details,
    this.label,
    this.color = const Color(0xFFFFFFFF),
  });

  /// The offer.
  final PlayStackNextUpDetails<Object?> details;

  /// The next item's name, such as "Episode 4".
  final String? label;

  /// Text color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final remaining = details.remaining;
    final seconds = remaining == null
        ? null
        : (remaining.inMilliseconds / 1000).ceil();
    return Material(
      color: const Color(0xD9000000),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      seconds == null ? 'Up next' : 'Up next in $seconds',
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Cancel',
                    onPressed: details.cancel,
                    icon: Icon(Icons.close_rounded, color: color, size: 18),
                  ),
                ],
              ),
            ),
            if (label case final label?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF000000),
                  backgroundColor: color,
                ),
                onPressed: details.playNow,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play now'),
              ),
            ),
            if (remaining != null)
              LinearProgressIndicator(
                value: details.progress,
                minHeight: 3,
                color: color,
                backgroundColor: color.withValues(alpha: 0.2),
              ),
          ],
        ),
      ),
    );
  }
}

/// Draws the skip button and the next-episode offer of a feed page.
@internal
class PlayStackSeriesLayer<T> extends StatefulWidget {
  /// Created by the feed view.
  const PlayStackSeriesLayer({
    super.key,
    required this.page,
    required this.series,
    required this.autoAdvance,
  });

  /// The page.
  final PlayStackFeedPage<T> page;

  /// The options.
  final PlayStackSeries<T> series;

  /// Whether the view moves on at the end by itself.
  final bool autoAdvance;

  @override
  State<PlayStackSeriesLayer<T>> createState() =>
      _PlayStackSeriesLayerState<T>();
}

class _PlayStackSeriesLayerState<T> extends State<PlayStackSeriesLayer<T>> {
  StreamSubscription<PlayStackPositionSnapshot>? _positions;
  PlayStackPlayerController? _controller;
  Duration _position = Duration.zero;
  bool _cancelled = false;
  bool _moved = false;

  /// How much of the countdown has passed; null while no offer shows.
  Duration? _counted;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(PlayStackSeriesLayer<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.isActive != widget.page.isActive ||
        !identical(oldWidget.page.controller, widget.page.controller)) {
      _follow();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _follow() {
    _stop();
    _cancelled = false;
    _moved = false;
    _counted = null;
    if (!widget.page.isActive) return;
    final controller = _controller = widget.page.controller
      ..addListener(_onState);
    _positions = controller.positions().listen((snapshot) {
      if (!mounted) return;
      final before = _position;
      _position = snapshot.position;
      // Seeking back before the offer starts it over.
      if (_position < before - const Duration(seconds: 2)) {
        _cancelled = false;
        _counted = null;
      }
      _update();
    }, onError: (Object _) {});
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_positions?.cancel());
    _positions = null;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isDisposed) {
      controller.removeListener(_onState);
    }
  }

  void _onState() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (controller.value.status == PlayStackPlaybackStatus.completed &&
        _offerVisible &&
        !widget.autoAdvance) {
      _playNext();
    }
  }

  List<PlayStackSkipMarker> get _markers =>
      widget.series.skipMarkers?.call(widget.page.data) ?? const [];

  T? get _next {
    final page = widget.page;
    final feed = page.feed;
    final index = page.index + 1;
    if (feed.isDisposed || index >= feed.length) return null;
    final item = feed.itemAt(index);
    if (!item.isVideo || item.locked) return null;
    return item.data as T;
  }

  /// Where the offer appears, or null when there is none.
  Duration? get _offerStart {
    final nextUp = widget.series.nextUp;
    if (nextUp == null) return null;
    final duration = widget.page.controller.value.duration;
    if (nextUp.atCredits) {
      for (final marker in _markers) {
        if (marker.type == PlayStackSkipMarkerType.credits) return marker.start;
      }
    }
    if (duration == null || duration <= Duration.zero) return null;
    final start = duration - nextUp.showBefore;
    return start.isNegative ? Duration.zero : start;
  }

  bool get _offerVisible {
    if (_cancelled || _moved || _next == null) return false;
    final start = _offerStart;
    final live = widget.page.controller.value.videoInfo?.isLive ?? false;
    return start != null && !live && _position >= start;
  }

  static const Duration _step = Duration(milliseconds: 200);

  void _update() {
    final countdown = widget.series.nextUp?.countdown ?? Duration.zero;
    if (_offerVisible && countdown > Duration.zero) {
      _counted ??= Duration.zero;
      _ticker ??= Timer.periodic(_step, (_) {
        if (!mounted) return;
        final counted = _counted;
        if (counted == null || !_offerVisible) {
          _ticker?.cancel();
          _ticker = null;
          setState(() {});
          return;
        }
        // The countdown waits while the video is paused.
        if (widget.page.controller.value.isPlaying) {
          _counted = counted + _step;
        }
        if (_counted! >= countdown) {
          _playNext();
          return;
        }
        setState(() {});
      });
    }
    setState(() {});
  }

  void _playNext() {
    if (_moved) return;
    _moved = true;
    _ticker?.cancel();
    _ticker = null;
    final view = widget.page.view;
    if (widget.page.feed.activeIndex.value == widget.page.index) {
      unawaited(view.nextPage().catchError((Object _) {}));
    }
    if (mounted) setState(() {});
  }

  void _cancel() {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _cancelled = true);
  }

  void _skip(PlayStackSkipMarker marker) {
    final controller = widget.page.controller;
    final duration = controller.value.duration;
    var target = marker.end;
    if (duration != null && target >= duration) {
      target = duration;
    }
    unawaited(controller.seekTo(target).catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    if (!page.isActive || page.isScreenLocked) return const SizedBox.shrink();
    final series = widget.series;
    Widget? child;
    final next = _next;
    if (_offerVisible && next != null) {
      final countdown = series.nextUp?.countdown ?? Duration.zero;
      final counted = _counted;
      final details = PlayStackNextUpDetails<T>(
        next: next,
        remaining: countdown <= Duration.zero || counted == null
            ? null
            : _clamp(countdown - counted, countdown),
        countdown: countdown,
        playNow: _playNext,
        cancel: _cancel,
      );
      child =
          series.nextUpBuilder?.call(context, page, details) ??
          PlayStackNextUpCard(
            details: details,
            label: series.nextUpLabel?.call(next),
          );
    } else {
      for (final marker in _markers) {
        if (!marker.contains(_position)) continue;
        // The offer takes the credits when there is a next episode.
        if (marker.type == PlayStackSkipMarkerType.credits &&
            series.nextUp != null &&
            next != null) {
          continue;
        }
        void skip() => _skip(marker);
        child =
            series.skipButtonBuilder?.call(context, page, marker, skip) ??
            PlayStackSkipButton(
              label: marker.label ?? marker.defaultLabel,
              onPressed: skip,
            );
        break;
      }
    }
    if (child == null) return const SizedBox.shrink();
    return Positioned(
      right: 16,
      bottom: page.isFullscreen ? 72 : 96,
      child: SafeArea(child: child),
    );
  }

  static Duration _clamp(Duration value, Duration max) => value.isNegative
      ? Duration.zero
      : value > max
      ? max
      : value;
}
