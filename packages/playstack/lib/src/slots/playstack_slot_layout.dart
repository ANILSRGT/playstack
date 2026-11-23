import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Builds a [PlayStackSlotLayout.custom] layout: place [video] (the video
/// with its controls) and [slot] (the ad or the cue) however you like.
typedef PlayStackSlotLayoutBuilder = Widget Function(
  BuildContext context,
  Widget video,
  Widget slot,
);

enum _Kind { fullScreen, videoArea, overlay, below, above, custom }

/// Where an ad break ([PlayStackAdBreak.layout]) or a cue
/// ([PlayStackCue.layout]) shows, relative to the video.
///
/// ```dart
/// PlayStackSlotLayout.fullScreen()                 // over the whole screen
/// PlayStackSlotLayout.videoArea()                  // over the video (default)
/// PlayStackSlotLayout.overlay(alignment: Alignment.bottomRight, widthFactor: 0.4)
/// PlayStackSlotLayout.below(height: 60)            // the video shrinks
/// PlayStackSlotLayout.above(height: 60)
/// PlayStackSlotLayout.custom((context, video, slot) => Row(children: [Expanded(child: video), SizedBox(width: 200, child: slot)]))
/// ```
@immutable
class PlayStackSlotLayout {
  /// Over the whole screen, above app bars, the controls and the feed.
  const PlayStackSlotLayout.fullScreen()
    : _kind = _Kind.fullScreen,
      alignment = Alignment.center,
      widthFactor = 1,
      aspectRatio = null,
      size = null,
      margin = EdgeInsets.zero,
      height = 0,
      safeArea = false,
      builder = null;

  /// Over the video and its controls, filling them. The default.
  const PlayStackSlotLayout.videoArea()
    : _kind = _Kind.videoArea,
      alignment = Alignment.center,
      widthFactor = 1,
      aspectRatio = null,
      size = null,
      margin = EdgeInsets.zero,
      height = 0,
      safeArea = false,
      builder = null;

  /// A box over the video, like a banner or a picture in picture: [size],
  /// or [widthFactor] of the video's width at [aspectRatio], placed at
  /// [alignment] inside [margin].
  const PlayStackSlotLayout.overlay({
    this.alignment = Alignment.bottomCenter,
    this.widthFactor = 0.9,
    this.aspectRatio = 16 / 9,
    this.size,
    this.margin = const EdgeInsets.all(12),
    this.safeArea = true,
  }) : _kind = _Kind.overlay,
       height = 0,
       builder = null;

  /// A strip [height] tall below the video; the video shrinks to make room
  /// and grows back after. With [safeArea], the strip also keeps clear of
  /// the home indicator.
  const PlayStackSlotLayout.below({required this.height, this.safeArea = true})
    : _kind = _Kind.below,
      alignment = Alignment.center,
      widthFactor = 1,
      aspectRatio = null,
      size = null,
      margin = EdgeInsets.zero,
      builder = null;

  /// A strip [height] tall above the video; the video shrinks to make room.
  const PlayStackSlotLayout.above({required this.height, this.safeArea = true})
    : _kind = _Kind.above,
      alignment = Alignment.center,
      widthFactor = 1,
      aspectRatio = null,
      size = null,
      margin = EdgeInsets.zero,
      builder = null;

  /// Your own arrangement of the video and the slot.
  const PlayStackSlotLayout.custom(PlayStackSlotLayoutBuilder this.builder)
    : _kind = _Kind.custom,
      alignment = Alignment.center,
      widthFactor = 1,
      aspectRatio = null,
      size = null,
      margin = EdgeInsets.zero,
      height = 0,
      safeArea = false;

  final _Kind _kind;

  /// Where an [PlayStackSlotLayout.overlay] box sits.
  final AlignmentGeometry alignment;

  /// The width of an overlay box, as a share of the video's width.
  final double widthFactor;

  /// Width / height of an overlay box sized by [widthFactor]; null lets the
  /// slot size itself.
  final double? aspectRatio;

  /// A fixed size for an overlay box; overrides [widthFactor].
  final Size? size;

  /// Space around an overlay box.
  final EdgeInsetsGeometry margin;

  /// The height of a strip above or below the video.
  final double height;

  /// Whether an overlay box or a strip keeps clear of notches and the home
  /// indicator.
  final bool safeArea;

  /// The builder of a [PlayStackSlotLayout.custom] layout.
  final PlayStackSlotLayoutBuilder? builder;

  /// Whether it covers the whole screen.
  bool get isFullScreen => _kind == _Kind.fullScreen;

  /// Whether it is a strip that shrinks the video.
  bool get isStrip => _kind == _Kind.below || _kind == _Kind.above;

  /// Places [slot] around [video].
  Widget apply(BuildContext context, Widget video, Widget slot) {
    switch (_kind) {
      case _Kind.fullScreen:
        return _FullScreenSlot(slot: slot, child: video);
      case _Kind.videoArea:
        return Stack(
          fit: StackFit.expand,
          children: [
            video,
            Positioned.fill(child: slot),
          ],
        );
      case _Kind.overlay:
        final fixed = size;
        final ratio = aspectRatio;
        Widget box = fixed != null
            ? SizedBox.fromSize(size: fixed, child: slot)
            : FractionallySizedBox(
                widthFactor: widthFactor,
                child: ratio == null
                    ? slot
                    : AspectRatio(aspectRatio: ratio, child: slot),
              );
        box = Padding(
          padding: margin,
          child: Align(alignment: alignment, child: box),
        );
        if (safeArea) box = SafeArea(child: box);
        return Stack(
          fit: StackFit.expand,
          children: [
            video,
            Positioned.fill(child: box),
          ],
        );
      case _Kind.below:
      case _Kind.above:
        Widget strip = SizedBox(
          height: height,
          width: double.infinity,
          child: slot,
        );
        if (safeArea) {
          strip = SafeArea(
            top: _kind == _Kind.above,
            bottom: _kind == _Kind.below,
            child: strip,
          );
        }
        return Column(
          children: [
            if (_kind == _Kind.above) strip,
            Expanded(child: video),
            if (_kind == _Kind.below) strip,
          ],
        );
      case _Kind.custom:
        return builder!(context, video, slot);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PlayStackSlotLayout &&
      other._kind == _kind &&
      other.alignment == alignment &&
      other.widthFactor == widthFactor &&
      other.aspectRatio == aspectRatio &&
      other.size == size &&
      other.margin == margin &&
      other.height == height &&
      other.safeArea == safeArea &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    _kind,
    alignment,
    widthFactor,
    aspectRatio,
    size,
    margin,
    height,
    safeArea,
    builder,
  );
}

class _FullScreenSlot extends StatefulWidget {
  const _FullScreenSlot({required this.slot, required this.child});

  final Widget slot;
  final Widget child;

  @override
  State<_FullScreenSlot> createState() => _FullScreenSlotState();
}

class _FullScreenSlotState extends State<_FullScreenSlot> {
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    // Without an Overlay (no Navigator above), fill what there is.
    if (Overlay.maybeOf(context, rootOverlay: true) == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned.fill(child: widget.slot),
        ],
      );
    }
    return OverlayPortal(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context) => Positioned.fill(child: widget.slot),
      child: widget.child,
    );
  }
}

/// Lays out the ads and cues shown inside it with their
/// [PlayStackSlotLayout]: wrap the video (and its controls) of your own
/// player, with a [PlayStackAdOverlay] or [PlayStackCueOverlay] somewhere
/// inside. `PlayStackFeedView` does this for every page.
///
/// ```dart
/// PlayStackSlotFrame(
///   child: Stack(children: [
///     PlayStackVideoView(controller: controller),
///     PlayStackAdOverlay(ads: ads),     // placed by each break's layout
///     PlayStackCueOverlay(cues: cues, builder: ...),
///   ]),
/// )
/// ```
///
/// Without a frame, an overlay fills the space it is given.
class PlayStackSlotFrame extends StatefulWidget {
  /// Creates a frame around [child].
  const PlayStackSlotFrame({super.key, required this.child});

  /// The video and its controls.
  final Widget child;

  /// The frame around [context], if any.
  static PlayStackSlotFrameState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SlotScope>()?.frame;

  @override
  State<PlayStackSlotFrame> createState() => PlayStackSlotFrameState();
}

/// The state of a [PlayStackSlotFrame]: what it shows and where.
class PlayStackSlotFrameState extends State<PlayStackSlotFrame> {
  // Keeps the video's subtree (players, controls, the overlays themselves)
  // alive when a layout moves it, for example into a column.
  final GlobalKey _videoKey = GlobalKey(debugLabel: 'PlayStackSlotFrame');
  final Map<Object, (PlayStackSlotLayout, WidgetBuilder)> _slots = {};

  /// Shows [builder] with [layout] for [owner], replacing what [owner]
  /// showed before; null removes it. Later owners are placed outside
  /// earlier ones.
  void show(Object owner, PlayStackSlotLayout? layout, WidgetBuilder? builder) {
    final current = _slots[owner];
    if (layout == null || builder == null) {
      if (current == null) return;
      _slots.remove(owner);
    } else {
      if (current != null &&
          current.$1 == layout &&
          identical(current.$2, builder)) {
        return;
      }
      _slots[owner] = (layout, builder);
    }
    _rebuild();
  }

  void _rebuild() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      // Asked during a build or layout: apply in the next frame.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = KeyedSubtree(key: _videoKey, child: widget.child);
    for (final (layout, builder) in _slots.values) {
      content = layout.apply(context, content, Builder(builder: builder));
    }
    return _SlotScope(frame: this, child: content);
  }
}

class _SlotScope extends InheritedWidget {
  const _SlotScope({required this.frame, required super.child});

  final PlayStackSlotFrameState frame;

  @override
  bool updateShouldNotify(_SlotScope oldWidget) => frame != oldWidget.frame;
}
