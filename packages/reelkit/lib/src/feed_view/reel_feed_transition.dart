import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Where a page is during a transition, passed to a custom transition (see
/// [ReelFeedTransition.custom]) for every visible page on every frame.
@immutable
class ReelFeedTransitionDetails {
  /// Creates transition details. `ReelFeedView` creates these; apps do not need to.
  const ReelFeedTransitionDetails({
    required this.offset,
    required this.axis,
    required this.reverse,
    required this.size,
  });

  /// Position of the page relative to the screen, in pages.
  ///
  /// * `0`: the page fills the screen.
  /// * Between `-1` and `0`: the page is before the one in view. When the user
  ///   swipes forward it is the page leaving; when swiping back, the page
  ///   coming back.
  /// * Between `0` and `1`: the page after the one in view, coming in.
  ///
  /// Halfway through a swipe forward the current page is at `-0.5` and the
  /// next at `0.5`. Use `offset.abs()` as the progress of a page's effect.
  final double offset;

  /// The swipe direction of the feed, `ReelFeedView.scrollDirection`.
  final Axis axis;

  /// Whether the feed is reversed (`ReelFeedView.reverse`): the next page comes
  /// from above or from the left.
  final bool reverse;

  /// Size of the feed on screen. Use it to compute distances.
  final Size size;

  /// The translation that cancels the scroll and keeps the page in place,
  /// as if it did not move. Pages normally slide with the finger; translate by
  /// [hold] to pin one, or by a fraction to slow it down:
  ///
  /// ```dart
  /// Transform.translate(offset: details.hold, child: child)        // stays
  /// Transform.translate(offset: details.hold * 0.5, child: child)  // half speed
  /// ```
  ///
  /// It already accounts for [axis] and [reverse].
  Offset get hold {
    final sign = reverse ? 1.0 : -1.0;
    return axis == Axis.vertical
        ? Offset(0, sign * offset * size.height)
        : Offset(sign * offset * size.width, 0);
  }
}

/// Builds one page during a transition: wrap [child] (the page) in
/// transforms, opacity or anything else, based on [details]. See
/// [ReelFeedTransition.custom].
typedef ReelFeedTransitionBuilder = Widget Function(
  BuildContext context,
  ReelFeedTransitionDetails details,
  Widget child,
);

/// How the pages of a `ReelFeedView` move from one to the next.
///
/// Pass one to `ReelFeedView.transition`:
///
/// ```dart
/// ReelFeedView(items: urls, transition: ReelFeedTransition.stack)
/// ```
///
/// Built-in transitions: [slide] (default), [parallax], [stack], [fade],
/// [zoom] and [cube]. Each one follows the finger while the user drags and
/// plays as an animation when the view moves from code
/// (`ReelFeedViewController.nextPage`).
///
/// For your own effect, use [ReelFeedTransition.custom], or extend this
/// class and override [build]. Pages are painted in index order, so the
/// next page is drawn above the current one.
abstract class ReelFeedTransition {
  /// Constructor for subclasses. Make it `const` so transitions can be constants.
  const ReelFeedTransition();

  /// A transition of your own. [builder] gets each visible page with its
  /// position ([ReelFeedTransitionDetails.offset]) and returns the page
  /// transformed:
  ///
  /// ```dart
  /// transition: ReelFeedTransition.custom((context, details, child) {
  ///   final progress = details.offset.abs().clamp(0.0, 1.0);
  ///   return Opacity(opacity: 1 - progress * 0.5, child: child);
  /// }),
  /// ```
  ///
  /// [builder] runs for every visible page on every frame of a swipe; keep it
  /// cheap (transforms and opacity, no layout work).
  const factory ReelFeedTransition.custom(ReelFeedTransitionBuilder builder) =
      _CustomTransition;

  /// Pages slide together, like a normal scrolling list. The default, and the cheapest.
  static const ReelFeedTransition slide = _SlideTransition();

  /// The current page moves at half speed while the next page slides over it,
  /// which adds depth.
  static const ReelFeedTransition parallax = _ParallaxTransition();

  /// The current page stays in place, shrinks and darkens while the next page
  /// slides over it, like a card laid on a deck.
  static const ReelFeedTransition stack = _StackTransition();

  /// Pages stay in place and cross-fade into each other.
  static const ReelFeedTransition fade = _FadeTransition();

  /// Pages stay in place: the next page grows in from slightly smaller while
  /// fading in, and the current page fades out.
  static const ReelFeedTransition zoom = _ZoomTransition();

  /// Pages turn in 3D like the faces of a cube rotating around its edge.
  static const ReelFeedTransition cube = _CubeTransition();

  /// Whether this transition leaves pages untouched. When true, `ReelFeedView`
  /// skips the per-frame transition work. Only [slide] returns true.
  bool get isIdentity => false;

  /// Builds [child], one page of the feed, at the position described by
  /// [details]. Called for every visible page on every frame of a swipe.
  Widget build(
    BuildContext context,
    ReelFeedTransitionDetails details,
    Widget child,
  );
}

class _CustomTransition extends ReelFeedTransition {
  const _CustomTransition(this.builder);

  final ReelFeedTransitionBuilder builder;

  @override
  Widget build(
    BuildContext context,
    ReelFeedTransitionDetails details,
    Widget child,
  ) => builder(context, details, child);
}

class _SlideTransition extends ReelFeedTransition {
  const _SlideTransition();

  @override
  bool get isIdentity => true;

  @override
  Widget build(
    BuildContext context,
    ReelFeedTransitionDetails details,
    Widget child,
  ) => child;
}

class _ParallaxTransition extends ReelFeedTransition {
  const _ParallaxTransition();

  @override
  Widget build(
    BuildContext context,
    ReelFeedTransitionDetails details,
    Widget child,
  ) {
    if (details.offset >= 0) return child;
    return Transform.translate(offset: details.hold * 0.5, child: child);
  }
}

class _StackTransition extends ReelFeedTransition {
  const _StackTransition();

  @override
  Widget build(
    BuildContext context,
    ReelFeedTransitionDetails details,
    Widget child,
  ) {
    if (details.offset >= 0) return child;
    final t = (-details.offset).clamp(0.0, 1.0);
    return Transform.translate(
      offset: details.hold,
      child: Transform.scale(
        scale: 1 - 0.12 * t,
        child: _Dim(amount: 0.6 * t, child: child),
      ),
    );
  }
}

class _FadeTransition extends ReelFeedTransition {
  const _FadeTransition();

  @override
  Widget build(
    BuildContext context,
    ReelFeedTransitionDetails details,
    Widget child,
  ) {
    final opacity = (1 - details.offset.abs()).clamp(0.0, 1.0);
    return Transform.translate(
      offset: details.hold,
      child: Opacity(opacity: opacity, child: child),
    );
  }
}

class _ZoomTransition extends ReelFeedTransition {
  const _ZoomTransition();

  @override
  Widget build(
    BuildContext context,
    ReelFeedTransitionDetails details,
    Widget child,
  ) {
    final t = details.offset.abs().clamp(0.0, 1.0);
    final scale = details.offset > 0 ? 1 - 0.15 * t : 1 + 0.08 * t;
    return Transform.translate(
      offset: details.hold,
      child: Opacity(
        opacity: 1 - t,
        child: Transform.scale(scale: scale, child: child),
      ),
    );
  }
}

class _CubeTransition extends ReelFeedTransition {
  const _CubeTransition();

  @override
  Widget build(
    BuildContext context,
    ReelFeedTransitionDetails details,
    Widget child,
  ) {
    final offset = details.offset.clamp(-1.0, 1.0);
    if (offset == 0) return child;
    final vertical = details.axis == Axis.vertical;
    // The page turns around the edge it shares with its neighbor: the
    // trailing edge of a page before the viewport, the leading edge of a
    // page after it.
    final before = offset < 0;
    final leadingFirst = !details.reverse;
    final hingeAtEnd = before == leadingFirst;
    final alignment = vertical
        ? (hingeAtEnd ? Alignment.bottomCenter : Alignment.topCenter)
        : (hingeAtEnd ? Alignment.centerRight : Alignment.centerLeft);
    final direction = details.reverse ? -1.0 : 1.0;
    final angle = offset * direction * math.pi / 2;
    final matrix = Matrix4.identity()..setEntry(3, 2, 0.0012);
    if (vertical) {
      matrix.rotateX(angle);
    } else {
      matrix.rotateY(-angle);
    }
    return Transform(
      alignment: alignment,
      transform: matrix,
      child: _Dim(amount: 0.5 * offset.abs(), child: child),
    );
  }
}

/// Darkens [child] by [amount] (0 to 1).
class _Dim extends StatelessWidget {
  const _Dim({required this.amount, required this.child});

  final double amount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Color.fromRGBO(0, 0, 0, amount.clamp(0.0, 1.0)),
            ),
          ),
        ),
      ],
    );
  }
}
