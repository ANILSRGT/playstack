import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The system's AirPlay button: a tap lists Apple TVs and AirPlay
/// speakers, and the playing video moves there. iOS only; on other
/// platforms it draws nothing (see `playstack_cast` for Chromecast).
///
/// ```dart
/// Row(children: [
///   PlayStackAirPlayButton(),
///   PlayStackCastButton(), // package:playstack_cast
/// ])
/// ```
///
/// The video plays on the TV with AVFoundation's external playback; the
/// app keeps controlling it (play, pause, seek). Protected (FairPlay)
/// streams are mirrored by the system.
class PlayStackAirPlayButton extends StatelessWidget {
  /// Creates an AirPlay button.
  const PlayStackAirPlayButton({
    super.key,
    this.size = 40,
    this.color = const Color(0xFFFFFFFF),
    this.activeColor = const Color(0xFF2196F3),
  });

  /// Width and height, 40 by default.
  final double size;

  /// Icon color.
  final Color color;

  /// Icon color while playing on another device.
  final Color activeColor;

  /// Whether AirPlay exists here (iOS).
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    if (!isSupported) return const SizedBox.shrink();
    return SizedBox.square(
      dimension: size,
      child: UiKitView(
        viewType: 'dev.playstack/airplay_button',
        creationParams: <String, Object>{
          'color': color.toARGB32(),
          'activeColor': activeColor.toARGB32(),
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
