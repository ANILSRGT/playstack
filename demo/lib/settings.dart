import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    // Prepare at up to ~540p and switch up once playing: a preparation then
    // downloads a fraction of a 1080p start, so several fit in the time
    // of a swipe.
    startupQualityLimit: const ReelVideoQualityLimit(maxBitrate: 1600000),
  ),
  audio: const ReelAudioConfig(
    // Play with the silent switch on, like video apps do.
    iosAudioSessionCategory: ReelAudioSessionCategory.playback,
  ),
  fullscreen: const ReelFullscreenConfig(
    appOrientations: [DeviceOrientation.portraitUp],
  ),
);

/// Five ahead, three at a time: at two or three swipes a second a smaller
/// window is outrun.
const demoFeedConfig = ReelFeedConfig(
  preloadAhead: 5,
  preloadBehind: 1,
  maxConcurrentPreloads: 3,
);
