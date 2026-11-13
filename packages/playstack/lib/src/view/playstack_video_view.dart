import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';

/// Builds what [PlayStackVideoView.placeholderBuilder] shows until the video's
/// first frame appears. [state] tells whether it is loading or idle.
typedef PlayStackPlaceholderBuilder = Widget Function(
  BuildContext context,
  PlayStackPlaybackState state,
);

/// Builds what [PlayStackVideoView.errorBuilder] shows when the video failed.
/// [error] tells what went wrong.
typedef PlayStackErrorBuilder = Widget Function(
  BuildContext context,
  PlayStackException error,
);

/// Shows the video of a [PlayStackPlayerController] on screen. It draws only the
/// picture: no buttons, no progress bar. Put your controls on top of it in
/// a [Stack].
///
/// ```dart
/// Stack(
///   fit: StackFit.expand,
///   children: [
///     PlayStackVideoView(
///       controller: controller,
///       fit: BoxFit.cover,
///       poster: NetworkImage(thumbnailUrl),
///     ),
///     MyControls(controller: controller),
///   ],
/// )
/// ```
///
/// The video is sized like an image: [fit] and [alignment] place it in the
/// available space, with rotation and pixel shape already applied.
/// [clipBehavior] and [borderRadius] clip it. Until the first frame appears
/// it shows [poster] and [placeholderBuilder]; if the video fails it shows
/// [errorBuilder].
///
/// `PlayStackFeedView` uses it for every page; you need it directly only for
/// your own layouts.
class PlayStackVideoView extends StatelessWidget {
  /// Creates a view that shows the video of [controller]. Defaults: the whole
  /// video visible ([BoxFit.contain]), centered, on black, clipped to the
  /// view.
  const PlayStackVideoView({
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

  /// The video to show. The view does not play it; call `play` on the controller.
  final PlayStackPlayerController controller;

  /// How the video fills the view, as for images. [BoxFit.contain] (default)
  /// shows the whole video with bars if needed; [BoxFit.cover] fills the view
  /// and crops the edges.
  final BoxFit fit;

  /// Where the video sits in the view when it does not fill it, or which part stays visible when cropped. Centered by default.
  final AlignmentGeometry alignment;

  /// Color behind the video, visible in the bars around it. Black by default.
  final Color backgroundColor;

  /// Whether and how the parts of the video outside the view are cut off. [Clip.hardEdge] by default.
  final Clip clipBehavior;

  /// Rounds the corners of the view. Needs a [clipBehavior] other than [Clip.none].
  final BorderRadiusGeometry? borderRadius;

  /// Image shown until the video's first frame appears, usually a thumbnail
  /// of that frame. Placed with the same [fit] and [alignment] as the video,
  /// so the switch is seamless.
  final ImageProvider? poster;

  /// Widget shown until the first frame appears, above [poster], for example
  /// a spinner or a title.
  final PlayStackPlaceholderBuilder? placeholderBuilder;

  /// Widget shown instead of the video when it failed, for example a message
  /// with a retry button calling `controller.retry()`. Without it, the view
  /// stays blank on errors.
  final PlayStackErrorBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayStackPlaybackState>(
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

  Widget _buildVideo(BuildContext context, PlayStackPlaybackState state) {
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

  final PlayStackVideoInfo info;
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
