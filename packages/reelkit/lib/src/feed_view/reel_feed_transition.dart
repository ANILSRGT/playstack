import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Where a page of a `ReelFeedView` is during a transition.
@immutable
class ReelFeedTransitionDetails {
  /// Creates transition details. `ReelFeedView` creates these.
  const ReelFeedTransitionDetails({
    required this.offset,
    required this.axis,
    required this.reverse,
    required this.size,
  });

  /// Position of the page relative to the viewport, in pages: 0 when it
  /// fills the viewport, -1 one page before (already left), 1 one page
  /// after (about to come in). Negative pages are leaving when the user
  /// moves forward and coming back when the user moves backward.
  final double offset;

  /// The scroll axis.
  final Axis axis;

  /// Whether the feed scrolls in reverse (next item from above or from the
  /// left).
  final bool reverse;

  /// Size of the viewport.
  final Size size;

  /// Translation that cancels the scroll movement and keeps the page where
  /// it would be at offset 0. Scale it to slow the page down: half of it
  /// moves the page at half the scroll speed.
  Offset get hold {
    final sign = reverse ? 1.0 : -1.0;
    return axis == Axis.vertical
        ? Offset(0, sign * offset * size.height)
        : Offset(sign * offset * size.width, 0);
  }
}

/// Builds a page of a `ReelFeedView` during a transition.
typedef ReelFeedTransitionBuilder = Widget Function(
  BuildContext context,
  ReelFeedTransitionDetails details,
  Widget child,
);

/// How pages of a `ReelFeedView` move from one to the next.
///
/// The transition follows the finger while the user drags and runs as an
/// animation for programmatic moves (`ReelFeedViewController.nextPage`).
/// Pages are painted in index order, so the next page is above the
/// current one.
///
/// Use one of the built-in transitions or describe your own with
/// [ReelFeedTransition.custom].
abstract class ReelFeedTransition {
  /// Const constructor for subclasses.
  const ReelFeedTransition();

  /// Describes a transition with [builder], called for every visible page
  /// on every scroll frame.
  const factory ReelFeedTransition.custom(ReelFeedTransitionBuilder builder) =
      _CustomTransition;

  /// Pages slide together, the default scroll behavior.
  static const ReelFeedTransition slide = _SlideTransition();

  /// The current page moves at half speed and the next page slides over it.
  static const ReelFeedTransition parallax = _ParallaxTransition();

  /// The current page stays, shrinks and darkens; the next page slides over
  /// it like a card on a deck.
  static const ReelFeedTransition stack = _StackTransition();

  /// Pages stay in place and cross-fade.
  static const ReelFeedTransition fade = _FadeTransition();

  /// The next page grows in from slightly smaller while fading in; the
  /// current page stays and fades out.
  static const ReelFeedTransition zoom = _ZoomTransition();

  /// Pages turn like the faces of a cube.
  static const ReelFeedTransition cube = _CubeTransition();

  /// Whether pages are shown untouched, letting `ReelFeedView` skip the
  /// per-frame transition work.
  bool get isIdentity => false;

  /// Builds [child], the page at [details].
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
