import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

/// The demo's loading animation, shown by the feed controls instead of the
/// SDK's spinner (`PlayStackDefaultControls.bufferingIndicator`).
class LoadingAnimation extends StatelessWidget {
  const LoadingAnimation({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) => Lottie.asset(
    'assets/animations/video_loading_helix.json',
    width: size,
    height: size,
  );
}
