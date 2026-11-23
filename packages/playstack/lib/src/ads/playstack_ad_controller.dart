import 'dart:async';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';
import '../manager/playstack_manager.dart';
import '../view/playstack_video_view.dart';
import '../slots/playstack_slot_layout.dart';
import 'playstack_ad.dart';

/// What happened to an ad break, for [PlayStackAdController.onEvent] and
/// [PlayStackFeedAds.onEvent].
enum PlayStackAdBreakEventType {
  /// `shouldShow` said no (or did not answer in time); nothing showed.
  declined,

  /// The break began: the ads load and show.
  started,

  /// The ad source had no ads (an ad server's empty answer).
  empty,

  /// An ad started playing.
  adStarted,

  /// An ad played to its end.
  adCompleted,

  /// The user skipped an ad.
  adSkipped,

  /// The user tapped "Learn more".
  adClicked,

  /// An ad, or loading the ads, failed.
  adFailed,

  /// The break is over; the video continues.
  ended,
}

/// An event of an ad break.
@immutable
class PlayStackAdBreakEvent {
  /// Creates an event.
  const PlayStackAdBreakEvent(
    this.type, {
    this.ad,
    this.adNumber,
    this.adCount,
  });

  /// What happened.
  final PlayStackAdBreakEventType type;

  /// The ad, for the `ad...` types.
  final PlayStackAd? ad;

  /// Which ad of the break (1-based), for the `ad...` types.
  final int? adNumber;

  /// How many ads the break has, once loaded.
  final int? adCount;

  @override
  String toString() =>
      'PlayStackAdBreakEvent(${type.name}${adNumber == null ? '' : ' $adNumber/$adCount'})';
}

/// Plays the ad breaks of a video: pauses it at each break (when the break
/// asks), plays the ads with their own player, reports impressions and
/// quartiles, lets the user skip when allowed, and resumes the video.
///
/// `PlayStackFeedView(ads: ...)` uses it for you. With your own player:
///
/// ```dart
/// final ads = PlayStackAdController(
///   manager: manager,
///   content: controller,
///   breaks: [
///     PlayStackAdBreak.preRoll(PlayStackAdSource.vast(preRollTag), id: 'pre'),
///     PlayStackAdBreak.midRoll(at: Duration(minutes: 5), id: 'mid', source: PlayStackAdSource.vast(midTag)),
///   ],
///   shouldShow: (adBreak) => myServer.canShow(adBreak.id), // optional
///   onEvent: (adBreak, event) => myServer.record(adBreak.id, event.type),
/// );
/// PlayStackSlotFrame(
///   child: Stack(children: [
///     PlayStackVideoView(controller: controller),
///     PlayStackAdOverlay(ads: ads), // the ad, "Skip", "Learn more"
///   ]),
/// );
/// // later
/// ads.dispose();
/// ```
class PlayStackAdController extends ChangeNotifier {
  /// Starts following [content] and plays [breaks] at their offsets.
  PlayStackAdController({
    required this.manager,
    required this.content,
    required List<PlayStackAdBreak> breaks,
    this.shouldShow,
    this.onEvent,
    this.decisionLead = const Duration(seconds: 5),
    this.decisionTimeout = const Duration(seconds: 3),
  }) : _pending = List<PlayStackAdBreak>.of(breaks) {
    content.addListener(_onContent);
    _positions = content
        .positions(interval: const Duration(milliseconds: 500))
        .listen(_onPosition, onError: (Object _) {});
    // The pre-roll is asked about at once, so the video rarely waits.
    for (final adBreak in _pending.where((b) => b.isPreRoll)) {
      unawaited(_decide(adBreak));
    }
    _onContent();
  }

  /// Creates the ad players.
  final PlayStackManager manager;

  /// The video the ads interrupt.
  final PlayStackPlayerController content;

  /// Asked before a break shows: true shows it, false skips it. Decide in
  /// your code, on the device or on your server; [PlayStackShowRules] has
  /// ready-made rules. Null shows every break.
  final FutureOr<bool> Function(PlayStackAdBreak adBreak)? shouldShow;

  /// Called for every [PlayStackAdBreakEvent]: to record what was shown, on
  /// the device or on your server.
  final void Function(PlayStackAdBreak adBreak, PlayStackAdBreakEvent event)?
  onEvent;

  /// How long before a break [shouldShow] is asked, so an answer from a
  /// server is there in time. Five seconds by default.
  final Duration decisionLead;

  /// How long the video waits for [shouldShow] when the break is reached
  /// and the answer is not there yet; then the break is skipped. Three
  /// seconds by default.
  final Duration decisionTimeout;

  final List<PlayStackAdBreak> _pending;
  final List<PlayStackAdBreak> _played = [];
  final Map<PlayStackAdBreak, Future<bool>> _decisions = {};
  final Map<PlayStackAdBreak, bool> _answers = {};
  StreamSubscription<PlayStackPositionSnapshot>? _positions;
  StreamSubscription<PlayStackPositionSnapshot>? _adPositions;
  bool _disposed = false;
  bool _running = false;
  bool _showing = false;
  bool _skipRequested = false;
  Completer<void>? _adDone;

  /// The break running now, or null.
  PlayStackAdBreak? get adBreak => _break;
  PlayStackAdBreak? _break;

  /// The ad playing now, or null.
  PlayStackAd? get ad => _ad;
  PlayStackAd? _ad;

  /// The player of the ad playing now; show it with `PlayStackVideoView`.
  PlayStackPlayerController? get adPlayer => _adPlayer;
  PlayStackPlayerController? _adPlayer;

  /// Which ad of the break plays (1-based), and how many there are.
  int get adNumber => _adNumber;
  int _adNumber = 0;

  /// How many ads the current break has.
  int get adCount => _adCount;
  int _adCount = 0;

  /// Where the ad is.
  Duration get adPosition => _adPosition;
  Duration _adPosition = Duration.zero;

  /// Whether an ad break shows (also while its ads load).
  bool get isPlayingAd => _showing;

  /// The breaks that have not run yet.
  List<PlayStackAdBreak> get pending =>
      List<PlayStackAdBreak>.unmodifiable(_pending);

  /// Time until the user may skip, zero when skippable now, null when the
  /// ad cannot be skipped.
  Duration? get skippableIn {
    final adBreak = _break;
    if (adBreak != null && !adBreak.skippable) return null;
    final skipAfter = adBreak?.skipAfter ?? _ad?.skipAfter;
    if (skipAfter == null || _ad == null) return null;
    final left = skipAfter - _adPosition;
    return left.isNegative ? Duration.zero : left;
  }

  /// Fires for every ad event, for your analytics.
  Stream<(PlayStackAd, PlayStackAdEvent)> get events => _events.stream;
  final StreamController<(PlayStackAd, PlayStackAdEvent)> _events =
      StreamController<(PlayStackAd, PlayStackAdEvent)>.broadcast();

  /// Fires for every [PlayStackAdBreakEvent], like [onEvent].
  Stream<(PlayStackAdBreak, PlayStackAdBreakEvent)> get breakEvents =>
      _breakEvents.stream;
  final StreamController<(PlayStackAdBreak, PlayStackAdBreakEvent)>
  _breakEvents =
      StreamController<(PlayStackAdBreak, PlayStackAdBreakEvent)>.broadcast();

  /// Skips the ad when [skippableIn] is zero.
  void skip() {
    final ad = _ad;
    if (ad == null || skippableIn != Duration.zero) return;
    _report(ad, PlayStackAdEvent.skip);
    _breakEvent(PlayStackAdBreakEventType.adSkipped, ad: ad);
    _skipRequested = true;
    _finishAd();
  }

  /// Reports a click and calls [PlayStackAds.onClick] with the advertiser's
  /// page.
  void click() {
    final ad = _ad;
    final url = ad?.clickThroughUrl;
    if (ad == null || url == null) return;
    _report(ad, PlayStackAdEvent.click);
    _breakEvent(PlayStackAdBreakEventType.adClicked, ad: ad);
    unawaited(_adPlayer?.pause().catchError((Object _) {}));
    PlayStackAds.onClick?.call(ad, url);
  }

  /// Pauses or resumes the ad.
  void togglePause() {
    final player = _adPlayer;
    final ad = _ad;
    if (player == null || ad == null) return;
    if (player.value.isPlaying) {
      _report(ad, PlayStackAdEvent.pause);
      unawaited(player.pause().catchError((Object _) {}));
    } else {
      _report(ad, PlayStackAdEvent.resume);
      unawaited(player.play().catchError((Object _) {}));
    }
  }

  /// Asks [shouldShow] about [adBreak] once (until it runs again).
  Future<bool> _decide(PlayStackAdBreak adBreak) {
    return _decisions[adBreak] ??= () async {
      final ask = shouldShow;
      if (ask == null) return _answers[adBreak] = true;
      try {
        return _answers[adBreak] = await ask(adBreak);
      } on Object catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'playstack',
            context: ErrorDescription('in shouldShow for $adBreak'),
          ),
        );
        return false;
      }
    }();
  }

  void _onContent() {
    if (_disposed || _running) return;
    final state = content.value;
    if (state.isPlaying) {
      final pre = _pending.where((b) => b.isPreRoll).firstOrNull;
      if (pre != null) unawaited(_runBreak(pre, resume: true));
    } else if (state.status == PlayStackPlaybackStatus.completed) {
      final post = _pending.where((b) => b.isPostRoll).firstOrNull;
      if (post != null) unawaited(_runBreak(post, resume: false));
    }
  }

  void _onPosition(PlayStackPositionSnapshot snapshot) {
    if (_disposed) return;
    final position = snapshot.position;
    // Seeking back before a played break that repeats brings it back.
    for (final adBreak in List<PlayStackAdBreak>.of(_played)) {
      final offset = adBreak.offset;
      if (!adBreak.repeatOnSeekBack || offset == null || adBreak.isPreRoll) {
        continue;
      }
      if (position + const Duration(seconds: 1) < offset) {
        _played.remove(adBreak);
        _decisions.remove(adBreak)?.ignore();
        _answers.remove(adBreak);
        _pending.add(adBreak);
      }
    }
    if (_running || !content.value.isPlaying) return;
    final duration = content.value.duration;
    for (final adBreak in _pending) {
      // Ask ahead of time.
      final at = adBreak.isPostRoll ? duration : adBreak.offset;
      if (at != null && position + decisionLead >= at) {
        unawaited(_decide(adBreak));
      }
    }
    for (final adBreak in _pending) {
      final offset = adBreak.offset;
      if (adBreak.isPostRoll || adBreak.isPreRoll || offset == null) continue;
      if (position >= offset) {
        // Seeking past several breaks plays only the last one.
        final skipped = _pending
            .where(
              (b) =>
                  !b.isPostRoll &&
                  !b.isPreRoll &&
                  b.offset != null &&
                  b.offset! < offset,
            )
            .toList();
        for (final b in skipped) {
          _pending.remove(b);
          _played.add(b);
        }
        unawaited(_runBreak(adBreak, resume: true));
        return;
      }
    }
  }

  Future<void> _runBreak(
    PlayStackAdBreak adBreak, {
    required bool resume,
  }) async {
    _pending.remove(adBreak);
    _played.add(adBreak);
    _running = true;
    final pause = adBreak.pauseContent;
    var allowed = _answers[adBreak];
    if (allowed == null) {
      // A late answer: a break that pauses the video makes it wait.
      if (pause) unawaited(content.pause().catchError((Object _) {}));
      try {
        allowed = await _decide(adBreak)
            .timeout(decisionTimeout, onTimeout: () => false);
      } on Object {
        allowed = false;
      }
    }
    if (_disposed) return;
    _decisions.remove(adBreak)?.ignore();
    _answers.remove(adBreak);
    if (!allowed) {
      _breakEvent(PlayStackAdBreakEventType.declined, adBreak: adBreak);
      _running = false;
      if (pause && resume && !content.value.isPlaying) {
        unawaited(content.play().catchError((Object _) {}));
      }
      return;
    }
    if (pause) unawaited(content.pause().catchError((Object _) {}));

    _break = adBreak;
    _showing = true;
    notifyListeners();
    _breakEvent(PlayStackAdBreakEventType.started);
    final wasMuted = content.value.isMuted;
    final muteContent = !pause && adBreak.muteContent && !wasMuted;
    if (muteContent) {
      unawaited(content.setMuted(true).catchError((Object _) {}));
    }
    try {
      final ads = await adBreak.source.load();
      _adCount = ads.length;
      if (ads.isEmpty) _breakEvent(PlayStackAdBreakEventType.empty);
      for (var i = 0; i < ads.length && !_disposed; i++) {
        _adNumber = i + 1;
        await _play(ads[i], adBreak);
      }
    } on Object catch (error, stack) {
      _breakEvent(PlayStackAdBreakEventType.adFailed);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'playstack',
          context: ErrorDescription('while loading ads'),
        ),
      );
    }
    if (_disposed) return;
    _breakEvent(PlayStackAdBreakEventType.ended);
    _running = false;
    _showing = false;
    _break = null;
    _ad = null;
    _adCount = 0;
    _adNumber = 0;
    _decisions.remove(adBreak)?.ignore();
    notifyListeners();
    if (muteContent && !content.isDisposed) {
      unawaited(content.setMuted(false).catchError((Object _) {}));
    }
    if (pause && resume && !content.isDisposed) {
      unawaited(content.play().catchError((Object _) {}));
    }
  }

  Future<void> _play(PlayStackAd ad, PlayStackAdBreak adBreak) async {
    final player = manager.createController(
      ad.source,
      // Ads never loop, whatever the app's settings. An ad next to the
      // playing video plays alongside it.
      config: manager.config.player.copyWith(
        looping: false,
        muted: adBreak.muteAd || manager.config.player.muted,
        exclusive: adBreak.pauseContent,
      ),
    );
    _ad = ad;
    _adPlayer = player;
    _adPosition = Duration.zero;
    _skipRequested = false;
    final done = _adDone = Completer<void>();
    final reached = <PlayStackAdEvent>{};
    var started = false;
    var finished = false;
    void onState() {
      final state = player.value;
      if (state.hasRenderedFirstFrame &&
          !reached.contains(PlayStackAdEvent.impression)) {
        reached.add(PlayStackAdEvent.impression);
        _report(ad, PlayStackAdEvent.impression);
      }
      if (state.isPlaying && !started) {
        started = true;
        _report(ad, PlayStackAdEvent.start);
        _breakEvent(PlayStackAdBreakEventType.adStarted, ad: ad);
      }
      if (finished) return;
      if (state.status == PlayStackPlaybackStatus.completed) {
        finished = true;
        _report(ad, PlayStackAdEvent.complete);
        _breakEvent(PlayStackAdBreakEventType.adCompleted, ad: ad);
        _finishAd();
      }
      if (state.hasError) {
        finished = true;
        _report(ad, PlayStackAdEvent.error);
        _breakEvent(PlayStackAdBreakEventType.adFailed, ad: ad);
        _finishAd();
      }
    }

    player.addListener(onState);
    _adPositions = player.positions().listen((snapshot) {
      _adPosition = snapshot.position;
      final duration = player.value.duration ?? ad.duration;
      if (duration != null && duration > Duration.zero) {
        final share =
            snapshot.position.inMilliseconds / duration.inMilliseconds;
        for (final (threshold, event) in const [
          (0.25, PlayStackAdEvent.firstQuartile),
          (0.5, PlayStackAdEvent.midpoint),
          (0.75, PlayStackAdEvent.thirdQuartile),
        ]) {
          if (share >= threshold && reached.add(event)) _report(ad, event);
        }
      }
      if (!_disposed) notifyListeners();
    }, onError: (Object _) {});
    notifyListeners();
    unawaited(
      player.play().catchError((Object _) {
        if (finished) return;
        finished = true;
        _report(ad, PlayStackAdEvent.error);
        _breakEvent(PlayStackAdBreakEventType.adFailed, ad: ad);
        _finishAd();
      }),
    );
    await done.future;
    player.removeListener(onState);
    await _adPositions?.cancel();
    _adPositions = null;
    _adPlayer = null;
    if (!_disposed) notifyListeners();
    await player.dispose();
  }

  void _finishAd() {
    final done = _adDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  void _report(PlayStackAd ad, PlayStackAdEvent event) {
    PlayStackAds.track(ad, event);
    if (!_events.isClosed) _events.add((ad, event));
  }

  void _breakEvent(
    PlayStackAdBreakEventType type, {
    PlayStackAd? ad,
    PlayStackAdBreak? adBreak,
  }) {
    final target = adBreak ?? _break;
    if (target == null || _disposed) return;
    final event = PlayStackAdBreakEvent(
      type,
      ad: ad,
      adNumber: ad == null ? null : _adNumber,
      adCount: _adCount == 0 ? null : _adCount,
    );
    try {
      onEvent?.call(target, event);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'playstack',
          context: ErrorDescription('in onEvent for $target'),
        ),
      );
    }
    if (!_breakEvents.isClosed) _breakEvents.add((target, event));
  }

  /// Whether the last ad was skipped by the user.
  @visibleForTesting
  bool get skipped => _skipRequested;

  @override
  void dispose() {
    _disposed = true;
    _finishAd();
    content.removeListener(_onContent);
    unawaited(_positions?.cancel());
    unawaited(_events.close());
    unawaited(_breakEvents.close());
    super.dispose();
  }
}

/// Builds the layer above an ad: labels and buttons. The ad video is drawn
/// below it.
typedef PlayStackAdBuilder = Widget Function(
  BuildContext context,
  PlayStackAdController ads,
);

/// Shows the ad of a [PlayStackAdController] while an ad break runs: the
/// ad, "Ad 1 of 2", a skip button and "Learn more". Draws nothing between
/// breaks.
///
/// Inside a [PlayStackSlotFrame] (every `PlayStackFeedView` page has one),
/// each break shows where its [PlayStackAdBreak.layout] says. Without a
/// frame, it fills the space it is given.
class PlayStackAdOverlay extends StatefulWidget {
  /// Creates the overlay of [ads]; [builder] replaces the labels and
  /// buttons.
  const PlayStackAdOverlay({
    super.key,
    required this.ads,
    this.builder,
    this.color = const Color(0xFFFFFFFF),
  });

  /// The ads.
  final PlayStackAdController ads;

  /// Replaces [PlayStackAdChrome].
  final PlayStackAdBuilder? builder;

  /// Text color of the default chrome.
  final Color color;

  @override
  State<PlayStackAdOverlay> createState() => _PlayStackAdOverlayState();
}

class _PlayStackAdOverlayState extends State<PlayStackAdOverlay> {
  PlayStackSlotFrameState? _frame;

  @override
  void initState() {
    super.initState();
    widget.ads.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final frame = PlayStackSlotFrame.maybeOf(context);
    if (!identical(frame, _frame)) {
      _frame?.show(this, null, null);
      _frame = frame;
    }
    _sync();
  }

  @override
  void didUpdateWidget(PlayStackAdOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ads, widget.ads)) {
      oldWidget.ads.removeListener(_sync);
      widget.ads.addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    final frame = _frame;
    if (frame == null) {
      if (mounted) setState(() {});
      return;
    }
    final adBreak = widget.ads.adBreak;
    if (widget.ads.isPlayingAd && adBreak != null) {
      frame.show(this, adBreak.layout, _content);
    } else {
      frame.show(this, null, null);
    }
  }

  Widget _content(BuildContext context) =>
      _AdContent(ads: widget.ads, builder: widget.builder, color: widget.color);

  @override
  void dispose() {
    widget.ads.removeListener(_sync);
    _frame?.show(this, null, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frame != null || !widget.ads.isPlayingAd) {
      return const SizedBox.shrink();
    }
    return _content(context);
  }
}

/// The ad itself: its video and the chrome.
class _AdContent extends StatelessWidget {
  const _AdContent({required this.ads, this.builder, required this.color});

  final PlayStackAdController ads;
  final PlayStackAdBuilder? builder;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ads,
      builder: (context, _) {
        if (!ads.isPlayingAd) return const SizedBox.shrink();
        final player = ads.adPlayer;
        return ColoredBox(
          color: const Color(0xFF000000),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (player != null)
                GestureDetector(
                  onTap: ads.togglePause,
                  child: PlayStackVideoView(
                    controller: player,
                    fit: BoxFit.contain,
                  ),
                ),
              builder?.call(context, ads) ??
                  PlayStackAdChrome(ads: ads, color: color),
            ],
          ),
        );
      },
    );
  }
}

/// The default labels and buttons of an ad.
class PlayStackAdChrome extends StatelessWidget {
  /// Creates the chrome of [ads].
  const PlayStackAdChrome({
    super.key,
    required this.ads,
    this.color = const Color(0xFFFFFFFF),
  });

  /// The ads.
  final PlayStackAdController ads;

  /// Text color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final skippableIn = ads.skippableIn;
    final ad = ads.ad;
    final style = TextStyle(color: color, fontSize: 13);
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  ads.adCount > 1
                      ? 'Ad ${ads.adNumber} of ${ads.adCount}'
                      : 'Ad',
                  style: const TextStyle(
                    color: Color(0xFF000000),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          if (ad?.clickThroughUrl != null)
            Positioned(
              left: 12,
              bottom: 24,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.7)),
                ),
                onPressed: ads.click,
                child: const Text('Learn more'),
              ),
            ),
          if (skippableIn != null)
            Positioned(
              right: 0,
              bottom: 24,
              child: Material(
                color: const Color(0xB3000000),
                child: InkWell(
                  onTap: skippableIn == Duration.zero ? ads.skip : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: skippableIn == Duration.zero
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Skip ad', style: style),
                              Icon(
                                Icons.skip_next_rounded,
                                color: color,
                                size: 20,
                              ),
                            ],
                          )
                        : Text(
                            'Skip in ${(skippableIn.inMilliseconds / 1000).ceil()}',
                            style: style,
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ads in a `PlayStackFeedView`: which breaks each item has, whether each
/// may show, what happened, and how the ad layer looks. Each break has its
/// own layout and settings ([PlayStackAdBreak]).
///
/// ```dart
/// PlayStackFeedView<Episode>(
///   items: episodes,
///   ads: PlayStackFeedAds(
///     breaks: (episode) => [
///       if (!user.isPremium)
///         PlayStackAdBreak.preRoll(PlayStackAdSource.vast(episode.adTag), id: 'pre'),
///     ],
///     // Optional: your own rule, on the device or on your server.
///     shouldShow: (episode, adBreak) => api.canShowAd(episode.id, adBreak.id),
///     onEvent: (episode, adBreak, event) => api.recordAd(episode.id, adBreak.id, event.type),
///   ),
/// )
/// ```
@immutable
class PlayStackFeedAds<T> {
  /// Creates feed ads.
  const PlayStackFeedAds({
    required this.breaks,
    this.builder,
    this.shouldShow,
    this.onEvent,
    this.decisionLead = const Duration(seconds: 5),
    this.decisionTimeout = const Duration(seconds: 3),
  });

  /// The ad breaks of an item; empty for none. Asked each time the item
  /// comes into view.
  final List<PlayStackAdBreak> Function(T item) breaks;

  /// Replaces the labels and buttons above the ad ([PlayStackAdChrome]).
  final PlayStackAdBuilder? builder;

  /// Asked before a break shows: true shows it, false skips it and the
  /// video goes on. Decide however you like: [PlayStackShowRules] on the
  /// device, your server, or the ad server alone (an empty VAST answer
  /// skips the break too). Null shows every break.
  final FutureOr<bool> Function(T item, PlayStackAdBreak adBreak)? shouldShow;

  /// Called for every [PlayStackAdBreakEvent], to record what was shown.
  final void Function(
    T item,
    PlayStackAdBreak adBreak,
    PlayStackAdBreakEvent event,
  )?
  onEvent;

  /// How long before a break [shouldShow] is asked.
  final Duration decisionLead;

  /// How long the video waits for a late [shouldShow] answer before the
  /// break is skipped.
  final Duration decisionTimeout;
}

/// Runs the ads of one feed page while it is in view.
@internal
class PlayStackFeedAdLayer<T> extends StatefulWidget {
  /// Created by the feed view.
  const PlayStackFeedAdLayer({
    super.key,
    required this.ads,
    required this.item,
    required this.controller,
    required this.manager,
    required this.isActive,
  });

  /// The options.
  final PlayStackFeedAds<T> ads;

  /// The item of the page.
  final T item;

  /// Its video.
  final PlayStackPlayerController controller;

  /// The feed's manager.
  final PlayStackManager manager;

  /// Whether the page is in view.
  final bool isActive;

  @override
  State<PlayStackFeedAdLayer<T>> createState() =>
      _PlayStackFeedAdLayerState<T>();
}

class _PlayStackFeedAdLayerState<T> extends State<PlayStackFeedAdLayer<T>> {
  PlayStackAdController? _ads;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PlayStackFeedAdLayer<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _ads?.dispose();
      _ads = null;
    }
    _sync();
  }

  /// One ad controller per visit of the page: created when it comes into
  /// view (breaks already played are not repeated while the page lives).
  void _sync() {
    if (!widget.isActive || _ads != null) return;
    final breaks = widget.ads.breaks(widget.item);
    if (breaks.isEmpty) return;
    final ads = widget.ads;
    final item = widget.item;
    final shouldShow = ads.shouldShow;
    final onEvent = ads.onEvent;
    _ads = PlayStackAdController(
      manager: widget.manager,
      content: widget.controller,
      breaks: breaks,
      decisionLead: ads.decisionLead,
      decisionTimeout: ads.decisionTimeout,
      shouldShow: shouldShow == null
          ? null
          : (adBreak) => shouldShow(item, adBreak),
      onEvent: onEvent == null
          ? null
          : (adBreak, event) => onEvent(item, adBreak, event),
    );
  }

  @override
  void dispose() {
    _ads?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ads = _ads;
    if (ads == null) return const SizedBox.shrink();
    return PlayStackAdOverlay(ads: ads, builder: widget.ads.builder);
  }
}
