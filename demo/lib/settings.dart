import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:reelkit/reelkit.dart';

/// ReelKit settings of the demo, tuned for swiping two or three videos a
/// second. `integration_test/swipe_test.dart` measures them.
ReelKitConfig demoKitConfig({bool muted = kIsWeb}) => ReelKitConfig(
  // The active item, five ahead and one behind.
  pool: const ReelPoolConfig(maxPlayers: 7),
  player: ReelPlayerConfig(
    looping: true,
    // Browsers block autoplay with sound until the user interacts, so the
    // web build starts muted; the mute button unmutes from a tap.
    muted: muted,
    // No rendition larger than the screen: a landscape video in the
    // portrait feed is as wide as the screen, so 1080p is wasted there and
    // its bandwidth (some streams under-declare it) can stall playback
    // while the next items preload. Fullscreen lifts this.
    videoQualityLimit: screenQualityLimit(),
    // Prepare at up to 720p and switch up once playing: a preparation then
    // downloads about half of a 1080p start, so several fit in the time of
    // a swipe, and the switch to 1080p is hardly visible.
    startupQualityLimit: const ReelVideoQualityLimit(maxBitrate: 3400000),
  ),
  audio: const ReelAudioConfig(
    // Play with the silent switch on, like video apps do.
    iosAudioSessionCategory: ReelAudioSessionCategory.playback,
  ),
  fullscreen: const ReelFullscreenConfig(
    appOrientations: [DeviceOrientation.portraitUp],
  ),
);

/// The screen in physical pixels, portrait. Unbounded where the size is
/// not known yet.
ReelVideoQualityLimit screenQualityLimit() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return ReelVideoQualityLimit.none;
  final size = views.first.physicalSize;
  if (size.isEmpty) return ReelVideoQualityLimit.none;
  return ReelVideoQualityLimit(
    maxWidth: size.shortestSide.round(),
    maxHeight: size.longestSide.round(),
  );
}

/// Five ahead, three at a time: at two or three swipes a second a smaller
/// window is outrun.
const demoFeedConfig = ReelFeedConfig(
  preloadAhead: 5,
  preloadBehind: 1,
  maxConcurrentPreloads: 3,
);
