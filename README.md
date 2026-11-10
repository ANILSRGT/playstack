# ReelKit

ReelKit is a video playback manager for Flutter, built for fast-scrolling video
feeds and for single players. It handles native players, pooling, lifecycle and
errors. You build the whole UI.

> **Status: milestone 3 (complete player API), development preview.**
> Playback works on Android (Media3), iOS (AVPlayer) and web (`<video>`):
> network, asset, file and memory sources; play, pause, stop, seek, loop,
> volume, mute and speed; source replacement; audio and subtitle tracks with
> subtitle text delivered to your UI; video quality caps; video metadata; a
> position stream; and pause/resume with the app lifecycle. Feed preloading,
> caching, fullscreen and audio sessions come in later milestones.

## Packages

| Package | Description |
| --- | --- |
| [`reelkit`](packages/reelkit) | The package applications depend on. |
| [`reelkit_platform_interface`](packages/reelkit_platform_interface) | Contract shared by the engines. |
| [`reelkit_android`](packages/reelkit_android) | Media3 ExoPlayer engine. |
| [`reelkit_ios`](packages/reelkit_ios) | AVFoundation engine. |
| [`reelkit_web`](packages/reelkit_web) | `HTMLVideoElement` engine. |

Architecture and decisions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Quick start

```dart
import 'package:reelkit/reelkit.dart';

final manager = ReelKitManager(
  config: const ReelKitConfig(
    pool: ReelPoolConfig(maxPlayers: 3), // omit for a device-adaptive limit
    player: ReelPlayerConfig(looping: true),
  ),
);
await manager.initialize();

final controller = manager.createController(
  ReelSource.network(
    'https://example.com/video.mp4',
    headers: {'Authorization': 'Bearer <token>'},
  ),
);

// Your UI: ReelKit only renders frames.
Stack(
  fit: StackFit.expand,
  children: [
    ReelVideoView(
      controller: controller,
      fit: BoxFit.cover,
      poster: const NetworkImage('https://example.com/poster.jpg'),
      errorBuilder: (context, error) => Center(child: Text(error.message)),
    ),
    // your buttons, progress bar, overlays...
  ],
);

await controller.play();           // prepares on demand
await controller.setSource(ReelSource.asset('assets/next.mp4')); // same player
controller.positions().listen(print); // polls only while playing
await controller.release();        // give the native player back, keep controller
await manager.dispose();           // releases every controller and player
```

## Concepts

- **`ReelKitManager`** owns the engine, the native player pool and its
  controllers. Use one per playback context, for example one per feed.
- **`ReelPlayerController`** controls one video. Creating it allocates
  nothing native; it leases a native player when initialized or played and
  returns it on `dispose`. Observe it as a
  `ValueListenable<ReelPlaybackState>`.
- **Pool.** At most `maxPlayers` native players exist. A controller with
  higher `priority` (`background < preload < visible < active`) can take the
  player of a lower one; that controller returns to `idle` and prepares again
  on its next `initialize` or `play`.
- **`release()`** gives a controller's native player back to the pool
  without disposing it; the pool detaches the source so the idle player
  holds no decoder or network resources.
- **Tracks and subtitles.** `controller.tracks` lists audio, video and
  subtitle tracks; `selectTrack`, `selectAutomaticTrack` and
  `disableSubtitles` change them; `controller.subtitles` delivers the subtitle
  text to show, which you render with your own widgets.
  `setVideoQualityLimit` caps adaptive video (bitrate and resolution).
  Selections are re-applied if the controller has to prepare again and are
  reset by `setSource`.
- **Lifecycle.** By default the manager pauses its playing controllers when
  the app is hidden and resumes them when it is shown again
  (`ReelLifecycleConfig`). `manager.pauseAll()` pauses everything, for
  example when another route covers the feed.
- **`ReelVideoView`** renders frames with any `BoxFit`, `Alignment`,
  background color, clipping and border radius, plus optional poster,
  placeholder and error builders. No controls.

## Platform support

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Engine | Media3 1.11.1 ExoPlayer | AVPlayer | HTMLVideoElement |
| Rendering | `SurfaceProducer` texture | `FlutterTexture` (`AVPlayerItemVideoOutput`) | Platform view |
| Play, pause, seek, loop, volume, mute, speed | Yes | Yes | Yes |
| First frame while paused (preparing ahead) | Yes | Yes | Yes |
| Rotation metadata | Yes | Yes | Applied by the browser |
| `ReelSource.network` | Yes | Yes | Yes |
| Custom HTTP headers | Yes | Yes (`AVURLAssetHTTPHeaderFieldsKey`) | No: `<video>` cannot send them; rejected with `invalidSource` |
| `ReelSource.asset` | Yes | Yes | Yes |
| `ReelSource.file` | Yes | Yes | No (`invalidSource`) |
| `ReelSource.memory` | Yes (in memory) | Yes (staged to a temporary file) | Yes (Blob URL) |
| HLS | Yes | Yes | Safari only; `unsupportedFormat` elsewhere |
| DASH | Yes | No (`unsupportedFormat`) | No (`unsupportedFormat`) |
| Autoplay with sound | Yes | Yes | Blocked by browsers until a user gesture (`playbackNotAllowed`); muted autoplay works |
| Disk cache | Milestone 6 | Milestone 6 | Browser cache only, no guarantees |
| Audio track selection | Yes | Yes (media selection) | Only where the browser exposes `audioTracks` (Safari) |
| Subtitle tracks, text delivered to Dart | Yes (in-band and HLS/DASH) | Yes (legible media selection) | Tracks the browser exposes (for example HLS in Safari); in-band MP4 text is not exposed by Chromium |
| Video rendition selection | Yes | No: AVFoundation chooses; listed for information | No |
| Video quality limit (bitrate, size) | Yes | Yes (`preferredPeakBitRate`, `preferredMaximumResolution`) | No (`notImplemented`) |
| Metadata: frame rate, bitrate, codec, live | Yes | Yes | Live flag only |
| Audio session / focus | Milestone 6 (host app's settings apply) | Milestone 6 (host app's `AVAudioSession` applies) | n/a |

`ReelPlatformCapabilities` reports these flags at runtime and never claims a
feature the engine does not provide.

Verified on device: the integration suite in
`packages/reelkit/example/integration_test` (20 tests: preparation, first
frame while paused, rotation, completion and restart, pause, loop, seek,
volume/mute/speed, memory source, missing source, pooled source switching,
100-source churn, metadata, audio and subtitle track selection with subtitle
text, source replacement, stop, position stream, quality limit, app
lifecycle) passes on an Android 16 emulator (API 36) and an iOS simulator. Rendering orientation was checked by screenshot against ffmpeg's
reference frame on both. Web is compiled (JS and Wasm) but its integration
suite has not been run yet (no chromedriver in the development setup).

## Errors

Every failure is a `ReelKitException` with a `ReelKitErrorCode`
(`network`, `decoder`, `sourceNotFound`, `poolExhausted`, `timeout`,
`notImplemented`, ...). Preparation errors are also exposed in
`controller.value.error`.

## Development

Requirements: Flutter 3.47+ (developed on 3.47.4), Dart 3.13+, JDK 17,
Xcode with iOS 15+ SDK.

```bash
flutter pub get                      # resolves the whole workspace
flutter analyze
flutter test packages/reelkit/test packages/reelkit_platform_interface/test \
  packages/reelkit_android/test packages/reelkit_ios/test
./tool/generate_pigeons.sh           # after editing pigeons/reelkit_messages.dart
```

Adding Swift files to `reelkit_ios` requires `pod install` in the example's
`ios` folder (CocoaPods snapshots the file list).

Device integration tests:

```bash
cd packages/reelkit/example
flutter test integration_test -d <device-id>
```

## Roadmap

1. Foundation — **done**: workspace, federated plugin, public API, platform
   interface, Pigeon bridge, player pool, example, tests.
2. Single native player — **done**: sources, play/pause/seek/loop, volume,
   speed, events, first frame, rotation, typed errors on all platforms.
3. Complete player API — **done**: tracks and subtitles, quality limits,
   metadata, source replacement, stop, position stream, app lifecycle.
4. Player manager: exclusive playback, decoder-failure-aware pool sizing.
5. Feed manager and intelligent preloading.
6. Cache, fullscreen and orientation coordination, audio sessions, retry.
7. Benchmarks, documentation, release.
