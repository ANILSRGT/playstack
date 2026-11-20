import 'dart:async';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';
import '../manager/playstack_manager.dart';
import '../view/playstack_video_view.dart';
import 'playstack_ad.dart';

/// Plays the ad breaks of a video: pauses it at each break, plays the ads
/// with their own player, reports impressions and quartiles, lets the user
/// skip when allowed, and resumes the video.
///
/// `PlayStackFeedView(ads: ...)` uses it for you. With your own player:
///
/// ```dart
/// final ads = PlayStackAdController(
///   manager: manager,
///   content: controller,
///   breaks: [
///     PlayStackAdBreak.preRoll(PlayStackAdSource.vast(preRollTag)),
///     PlayStackAdBreak.midRoll(at: Duration(minutes: 5), source: PlayStackAdSource.vast(midTag)),
///   ],
/// );
/// Stack(children: [
///   PlayStackVideoView(controller: controller),
///   PlayStackAdOverlay(ads: ads), // the ad, "Skip", "Learn more"
/// ]);
/// // later
/// ads.dispose();
/// ```
class PlayStackAdController extends ChangeNotifier {
  /// Starts following [content] and plays [breaks] at their offsets.
  PlayStackAdController({
    required this.manager,
    required this.content,
    required List<PlayStackAdBreak> breaks,
  }) : _pending = List<PlayStackAdBreak>.of(breaks) {
    content.addListener(_onContent);
    _positions = content
        .positions(interval: const Duration(milliseconds: 500))
        .listen(_onPosition, onError: (Object _) {});
    _onContent();
  }

  /// Creates the ad players.
  final PlayStackManager manager;

  /// The video the ads interrupt.
  final PlayStackPlayerController content;

  final List<PlayStackAdBreak> _pending;
  StreamSubscription<PlayStackPositionSnapshot>? _positions;
  StreamSubscription<PlayStackPositionSnapshot>? _adPositions;
  bool _disposed = false;
  bool _running = false;
  bool _skipRequested = false;
  Completer<void>? _adDone;

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

  /// Whether an ad break is running (also while its ads load).
  bool get isPlayingAd => _running;

  /// Time until the user may skip, zero when skippable now, null when the
  /// ad cannot be skipped.
  Duration? get skippableIn {
    final skipAfter = _ad?.skipAfter;
    if (skipAfter == null) return null;
    final left = skipAfter - _adPosition;
    return left.isNegative ? Duration.zero : left;
  }

  /// Fires for every ad event, for your analytics.
  Stream<(PlayStackAd, PlayStackAdEvent)> get events => _events.stream;
  final StreamController<(PlayStackAd, PlayStackAdEvent)> _events =
      StreamController<(PlayStackAd, PlayStackAdEvent)>.broadcast();

  /// Skips the ad when [skippableIn] is zero.
  void skip() {
    final ad = _ad;
    if (ad == null || skippableIn != Duration.zero) return;
    _report(ad, PlayStackAdEvent.skip);
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
    if (_disposed || _running || !content.value.isPlaying) return;
    for (final adBreak in _pending) {
      final offset = adBreak.offset;
      if (adBreak.isPostRoll || adBreak.isPreRoll || offset == null) continue;
      if (snapshot.position >= offset) {
        // Seeking past several breaks plays only the last one.
        _pending.removeWhere(
          (b) =>
              !b.isPostRoll &&
              !b.isPreRoll &&
              b.offset != null &&
              b.offset! < offset,
        );
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
    _running = true;
    notifyListeners();
    unawaited(content.pause().catchError((Object _) {}));
    try {
      final ads = await adBreak.source.load();
      _adCount = ads.length;
      for (var i = 0; i < ads.length && !_disposed; i++) {
        _adNumber = i + 1;
        await _play(ads[i]);
      }
    } on Object catch (error, stack) {
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
    _running = false;
    _ad = null;
    _adCount = 0;
    _adNumber = 0;
    notifyListeners();
    if (resume) unawaited(content.play().catchError((Object _) {}));
  }

  Future<void> _play(PlayStackAd ad) async {
    final player = manager.createController(ad.source);
    // Ads never loop, whatever the app's settings.
    unawaited(player.setLooping(false).catchError((Object _) {}));
    _ad = ad;
    _adPlayer = player;
    _adPosition = Duration.zero;
    _skipRequested = false;
    final done = _adDone = Completer<void>();
    final reached = <PlayStackAdEvent>{};
    var started = false;
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
      }
      if (state.status == PlayStackPlaybackStatus.completed) {
        _report(ad, PlayStackAdEvent.complete);
        _finishAd();
      }
      if (state.hasError) {
        _report(ad, PlayStackAdEvent.error);
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
        _report(ad, PlayStackAdEvent.error);
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
    super.dispose();
  }
}

/// Builds the layer above an ad: labels and buttons. The ad video is drawn
/// below it.
typedef PlayStackAdBuilder = Widget Function(
  BuildContext context,
  PlayStackAdController ads,
);

/// Shows the ad of a [PlayStackAdController] above the video while an ad
/// break runs: the ad, "Ad 1 of 2", a skip button and "Learn more". Draws
/// nothing between breaks.
class PlayStackAdOverlay extends StatelessWidget {
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

/// Ads in a `PlayStackFeedView`: which breaks each item has, and how the ad
/// layer looks.
///
/// ```dart
/// PlayStackFeedView<Episode>(
///   items: episodes,
///   ads: PlayStackFeedAds(
///     breaks: (episode) => [
///       if (!user.isPremium)
///         PlayStackAdBreak.preRoll(PlayStackAdSource.vast(episode.adTag)),
///     ],
///   ),
/// )
/// ```
@immutable
class PlayStackFeedAds<T> {
  /// Creates feed ads.
  const PlayStackFeedAds({required this.breaks, this.builder});

  /// The ad breaks of an item; empty for none.
  final List<PlayStackAdBreak> Function(T item) breaks;

  /// Replaces the labels and buttons above the ad ([PlayStackAdChrome]).
  final PlayStackAdBuilder? builder;
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
    _ads = PlayStackAdController(
      manager: widget.manager,
      content: widget.controller,
      breaks: breaks,
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
