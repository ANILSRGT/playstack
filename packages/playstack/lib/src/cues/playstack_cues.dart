import 'dart:async';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_player_controller.dart';
import '../feed_view/playstack_feed_view.dart';

/// A moment in a video where the app shows something of its own: a poll,
/// a "rate this episode" card, a banner, an interstitial ad of your ad
/// SDK.
///
/// ```dart
/// PlayStackCue(at: Duration(seconds: 30), id: 'poll')
/// PlayStackCue.fromEnd(Duration(seconds: 15), id: 'rate', pause: false)
/// PlayStackCue(at: Duration(minutes: 5), id: 'admob', pause: true)
/// ```
///
/// A cue fires once per visit, when playback reaches it. Seeking past a
/// cue does not fire it. [PlayStackFeedCues] (in a feed) and
/// [PlayStackCueController] (with your own player) run them.
@immutable
class PlayStackCue {
  /// A cue [at] a position from the start. [Duration.zero] fires when the
  /// video first starts playing.
  const PlayStackCue({
    required Duration this.at,
    this.id,
    this.pause = false,
    this.showFor,
    this.data,
  }) : fromEnd = null;

  /// A cue [fromEnd] before the end of the video, for example the last 15
  /// seconds. It is placed once the length is known.
  const PlayStackCue.fromEnd(
    Duration this.fromEnd, {
    this.id,
    this.pause = false,
    this.showFor,
    this.data,
  }) : at = null;

  /// The position from the start, or null for a [fromEnd] cue.
  final Duration? at;

  /// The time before the end, or null for an [at] cue.
  final Duration? fromEnd;

  /// Your name for the cue, to tell cues apart in the handler.
  final String? id;

  /// Whether the video pauses while the cue is shown and plays again
  /// after. False by default: the cue shows over the playing video.
  final bool pause;

  /// Ends the cue on its own after this long. Null (the default) waits for
  /// the handler or for `dismiss`.
  final Duration? showFor;

  /// Anything you want to attach: the poll's question, an ad unit id.
  final Object? data;

  /// Where the cue fires in a video of [duration]; null while unknown.
  Duration? positionIn(Duration? duration) {
    final from = at;
    if (from != null) return from;
    if (duration == null || duration <= Duration.zero) return null;
    final position = duration - fromEnd!;
    return position.isNegative ? Duration.zero : position;
  }

  @override
  String toString() =>
      'PlayStackCue(${id ?? ''} ${at != null ? 'at $at' : '$fromEnd before end'})';
}

/// Runs [PlayStackCue]s on one video: notices when playback reaches each,
/// pauses the video when the cue asks, calls [onCue], and tells you which
/// cue is showing ([active]).
///
/// `PlayStackFeedView(cues: ...)` uses it for you. With your own player:
///
/// ```dart
/// final cues = PlayStackCueController(
///   controller: controller,
///   cues: [PlayStackCue(at: Duration(seconds: 30), id: 'poll', pause: true)],
///   onCue: (cue) => showPollDialog(context), // the video waits for it
/// );
/// // later
/// cues.dispose();
/// ```
///
/// A cue ends when [onCue]'s future completes, when its
/// [PlayStackCue.showFor] runs out, or when you call [dismiss]. With
/// [endWhenHandled] false (for a cue shown as a widget over the video), only
/// [dismiss] and `showFor` end it.
class PlayStackCueController extends ChangeNotifier {
  /// Starts following [controller].
  PlayStackCueController({
    required this.controller,
    required List<PlayStackCue> cues,
    this.onCue,
    this.endWhenHandled = true,
    bool Function()? canResume,
  }) : _pending = List<PlayStackCue>.of(cues),
       // ignore: prefer_initializing_formals, a private named parameter
       _canResume = canResume {
    controller.addListener(_onState);
    _positions = controller
        .positions(interval: const Duration(milliseconds: 250))
        .listen(_onPosition, onError: (Object _) {});
    _onState();
  }

  /// The video.
  final PlayStackPlayerController controller;

  /// Called when a cue fires. The cue stays [active] until the returned
  /// future completes (see [endWhenHandled]).
  final FutureOr<void> Function(PlayStackCue cue)? onCue;

  /// Whether a cue ends when [onCue] completes. True by default.
  final bool endWhenHandled;

  final bool Function()? _canResume;
  final List<PlayStackCue> _pending;
  StreamSubscription<PlayStackPositionSnapshot>? _positions;
  Duration? _last;
  bool _disposed = false;
  Completer<void>? _done;
  Timer? _timer;

  /// The cue showing now, or null.
  PlayStackCue? get active => _active;
  PlayStackCue? _active;

  /// The cues that have not fired yet.
  List<PlayStackCue> get pending => List<PlayStackCue>.unmodifiable(_pending);

  /// Fires with every cue as it starts.
  Stream<PlayStackCue> get cues => _cues.stream;
  final StreamController<PlayStackCue> _cues =
      StreamController<PlayStackCue>.broadcast();

  /// Ends the [active] cue; the video plays again if the cue paused it.
  void dismiss() {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Fires [cue] now, whatever the position.
  Future<void> fire(PlayStackCue cue) => _fire(cue);

  void _onState() {
    if (_disposed || _active != null) return;
    if (!controller.value.isPlaying) return;
    final start = _pending.where((cue) => cue.at == Duration.zero).firstOrNull;
    if (start != null) unawaited(_fire(start));
  }

  void _onPosition(PlayStackPositionSnapshot snapshot) {
    if (_disposed) return;
    final position = snapshot.position;
    final last = _last;
    _last = position;
    if (last == null || _active != null || !controller.value.isPlaying) {
      return;
    }
    // A jump (seek, or a new visit) does not fire the cues it passes.
    final step = position - last;
    if (step.isNegative || step > const Duration(seconds: 2)) return;
    final duration = controller.value.duration;
    for (final cue in _pending) {
      final at = cue.positionIn(duration);
      if (at == null || at == Duration.zero) continue;
      if (at > last && at <= position) {
        unawaited(_fire(cue));
        return;
      }
    }
  }

  Future<void> _fire(PlayStackCue cue) async {
    if (_disposed || _active != null) return;
    _pending.remove(cue);
    _active = cue;
    final done = _done = Completer<void>();
    final wasPlaying = controller.value.isPlaying;
    if (cue.pause) unawaited(controller.pause().catchError(_ignore));
    notifyListeners();
    _cues.add(cue);
    final showFor = cue.showFor;
    if (showFor != null) _timer = Timer(showFor, dismiss);
    try {
      final handled = onCue?.call(cue);
      if (handled is Future<void>) await handled;
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'playstack',
          context: ErrorDescription('while handling a cue'),
        ),
      );
    }
    if (endWhenHandled) dismiss();
    await done.future;
    _timer?.cancel();
    _timer = null;
    if (_disposed) return;
    _active = null;
    _done = null;
    // Positions read while the cue showed are not steps of playback.
    _last = null;
    notifyListeners();
    if (cue.pause &&
        wasPlaying &&
        !controller.isDisposed &&
        (_canResume?.call() ?? true)) {
      unawaited(controller.play().catchError(_ignore));
    }
  }

  static void _ignore(Object _) {}

  @override
  void dispose() {
    _disposed = true;
    dismiss();
    _timer?.cancel();
    controller.removeListener(_onState);
    unawaited(_positions?.cancel());
    unawaited(_cues.close());
    super.dispose();
  }
}

/// A move from one item of a feed to another, passed to
/// [PlayStackFeedCues.onTransition].
@immutable
class PlayStackTransition<T> {
  /// Created by the feed view.
  const PlayStackTransition({
    required this.from,
    required this.to,
    required this.fromIndex,
    required this.toIndex,
    required this.count,
  });

  /// The item left.
  final T from;

  /// The item coming into view.
  final T to;

  /// The index of [from].
  final int fromIndex;

  /// The index of [to].
  final int toIndex;

  /// How many moves the user made in this feed, this one included: 1 for
  /// the first. `count % 5 == 0` shows something every fifth video.
  final int count;

  /// Whether the user moved forward.
  bool get isForward => toIndex > fromIndex;
}

/// Builds what a feed shows over a video while a cue is active. Call
/// `dismiss` to end the cue.
typedef PlayStackCueBuilder<T> = Widget Function(
  BuildContext context,
  PlayStackFeedPage<T> page,
  PlayStackCue cue,
  VoidCallback dismiss,
);

/// Your moments in the videos of a [PlayStackFeedView]: cues at positions
/// of each item, and a hook between items. All optional; the feed shows and
/// decides nothing on its own.
///
/// ```dart
/// PlayStackFeedView<Episode>(
///   items: episodes,
///   cues: PlayStackFeedCues(
///     // A poll 30 seconds into every episode, over the playing video.
///     cues: (episode) => [PlayStackCue(at: Duration(seconds: 30), id: 'poll')],
///     builder: (context, page, cue, dismiss) => PollCard(onClose: dismiss),
///
///     // An interstitial of your ad SDK between episodes: the next episode
///     // starts when the future completes.
///     onTransition: (context, move) async {
///       if (move.isForward && move.count % 3 == 0) {
///         await myInterstitial.show();
///       }
///     },
///   ),
/// )
/// ```
class PlayStackFeedCues<T> {
  /// Creates the cues of a feed.
  const PlayStackFeedCues({
    this.cues,
    this.onCue,
    this.builder,
    this.onTransition,
  });

  /// The cues of an item. Null or an empty list for none.
  final List<PlayStackCue> Function(T item)? cues;

  /// Called when a cue fires. Without a [builder], the cue ends when the
  /// returned future completes (a paused video then plays again).
  final FutureOr<void> Function(
    BuildContext context,
    PlayStackFeedPage<T> page,
    PlayStackCue cue,
  )?
  onCue;

  /// Draws the active cue over the video, above the controls. The cue ends
  /// when it calls `dismiss` (or after [PlayStackCue.showFor]).
  final PlayStackCueBuilder<T>? builder;

  /// Called when the user moves to another item (or the feed advances on
  /// its own). The new item waits, paused, until the returned future
  /// completes: show an interstitial ad, a dialog, a paywall. Return at once
  /// to let it play.
  final Future<void> Function(
    BuildContext context,
    PlayStackTransition<T> transition,
  )?
  onTransition;
}

/// Runs the cues of one feed page. Created by the feed view.
@internal
class PlayStackFeedCueLayer<T> extends StatefulWidget {
  /// Created by the feed view.
  const PlayStackFeedCueLayer({
    super.key,
    required this.cues,
    required this.page,
  });

  /// The options.
  final PlayStackFeedCues<T> cues;

  /// The page.
  final PlayStackFeedPage<T> page;

  @override
  State<PlayStackFeedCueLayer<T>> createState() =>
      _PlayStackFeedCueLayerState<T>();
}

class _PlayStackFeedCueLayerState<T> extends State<PlayStackFeedCueLayer<T>> {
  PlayStackCueController? _cues;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PlayStackFeedCueLayer<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.page.controller, widget.page.controller)) {
      _cues?.dispose();
      _cues = null;
    }
    // A cue does not follow the user to another page.
    if (!widget.page.isActive) _cues?.dismiss();
    _sync();
  }

  /// One cue controller per page: cues fire once while the page lives.
  void _sync() {
    if (!widget.page.isActive || _cues != null) return;
    final cues = widget.cues.cues?.call(widget.page.data) ?? const [];
    if (cues.isEmpty) return;
    final onCue = widget.cues.onCue;
    _cues = PlayStackCueController(
      controller: widget.page.controller,
      cues: cues,
      endWhenHandled: widget.cues.builder == null,
      canResume: () => mounted && widget.page.isActive,
      onCue: onCue == null ? null : (cue) => onCue(context, widget.page, cue),
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cues?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cues = _cues;
    final cue = cues?.active;
    final builder = widget.cues.builder;
    if (cues == null || cue == null || builder == null) {
      return const SizedBox.shrink();
    }
    return builder(context, widget.page, cue, cues.dismiss);
  }
}
