import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../controller/reel_playback_state.dart';
import '../controller/reel_player_controller.dart';

/// Builds a widget shown in place of the video, for example while it is
/// preparing.
typedef ReelPlaceholderBuilder = Widget Function(
  BuildContext context,
  ReelPlaybackState state,
);

/// Builds a widget shown when playback failed.
typedef ReelErrorBuilder = Widget Function(
  BuildContext context,
  ReelKitException error,
);

/// Displays the video of a [ReelPlayerController].
///
/// This widget only renders frames. It has no controls: build play buttons,
/// progress bars and overlays yourself on top of it, typically in a [Stack].
///
/// Layout: the video is laid out at its display size (pixel aspect ratio and
/// rotation applied) and fitted into the available space with [fit] and
/// [alignment], exactly like an image. Content outside the bounds is clipped
/// according to [clipBehavior] and [borderRadius].
///
/// Until the first frame is rendered, [poster] or [placeholderBuilder] is
/// shown. When the controller is in an error state, [errorBuilder] is shown.
class ReelVideoView extends StatelessWidget {
  const ReelVideoView({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.backgroundColor = const Color(0xFF000000),
    this.clipBehavior = Clip.hardEdge,
    this.borderRadius,
    this.poster,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  final ReelPlayerController controller;

  /// How the video is inscribed into the available space.
  final BoxFit fit;

  /// Where the video is placed within the available space.
  final AlignmentGeometry alignment;

  /// Painted behind the video, visible in letterbox areas.
  final Color backgroundColor;

  /// How content outside the view bounds is clipped.
  final Clip clipBehavior;

  /// Rounds the corners of the view. Requires [clipBehavior] other than
  /// [Clip.none].
  final BorderRadiusGeometry? borderRadius;

  /// Image shown until the first frame is rendered, laid out with [fit] and
  /// [alignment].
  final ImageProvider? poster;

  /// Shown until the first frame is rendered, above [poster].
  final ReelPlaceholderBuilder? placeholderBuilder;

  /// Shown instead of the video when the controller has an error.
  final ReelErrorBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReelPlaybackState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final error = state.error;
        final Widget content;
        if (state.hasError && error != null && errorBuilder != null) {
          content = errorBuilder!(context, error);
        } else {
          content = _buildVideo(context, state);
        }
        return _clip(ColoredBox(color: backgroundColor, child: content));
      },
    );
  }

  Widget _buildVideo(BuildContext context, ReelPlaybackState state) {
    final info = state.videoInfo;
    final nativeView = controller.buildNativeView();
    final showsVideo = nativeView != null && info != null && info.hasSize;
    final children = <Widget>[
      if (showsVideo)
        _FittedVideo(
          info: info,
          fit: fit,
          alignment: alignment,
          child: nativeView,
        ),
      if (!state.hasRenderedFirstFrame && poster != null)
        Positioned.fill(
          child: Image(
            image: poster!,
            fit: fit,
            alignment: alignment,
            gaplessPlayback: true,
          ),
        ),
      if (!state.hasRenderedFirstFrame && placeholderBuilder != null)
        Positioned.fill(child: placeholderBuilder!(context, state)),
    ];
    return Stack(fit: StackFit.expand, children: children);
  }

  Widget _clip(Widget child) {
    if (clipBehavior == Clip.none) return child;
    final radius = borderRadius;
    if (radius != null) {
      return ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: child,
      );
    }
    return ClipRect(clipBehavior: clipBehavior, child: child);
  }
}

/// Lays the native view out at the video's display size, applies the
/// rotation the engine did not apply, and fits the result into the parent.
class _FittedVideo extends StatelessWidget {
  const _FittedVideo({
    required this.info,
    required this.fit,
    required this.alignment,
    required this.child,
  });

  final ReelVideoInfo info;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final display = info.displaySize;
    final quarterTurns = (info.rotationDegrees ~/ 90) % 4;
    // The texture is laid out at its native orientation; RotatedBox swaps the
    // axes for odd quarter turns so the outer box matches `display`.
    final textureSize = quarterTurns.isOdd
        ? Size(display.height, display.width)
        : display;
    final video = RotatedBox(
      quarterTurns: quarterTurns,
      child: SizedBox(
        width: textureSize.width,
        height: textureSize.height,
        child: child,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          // FittedBox needs bounds; in unbounded layouts size by aspect ratio.
          return AspectRatio(
            aspectRatio: info.aspectRatio,
            child: FittedBox(fit: BoxFit.fill, child: video),
          );
        }
        return FittedBox(
          fit: fit,
          alignment: alignment,
          clipBehavior: Clip.none,
          child: video,
        );
      },
    );
  }
}
