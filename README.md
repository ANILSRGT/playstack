# ReelKit

ReelKit is a video playback manager for Flutter, built for fast-scrolling video
feeds and for single players. It handles native players, pooling, lifecycle and
errors. You build the whole UI.

> **Status: milestone 1 (foundation), development preview.** The architecture,
> public Dart API, player pool, typed native bridge and native player
> allocation work on Android, iOS and web. **Video playback itself is not
> available yet.** `setSource`, `play` and the other playback commands report
> `ReelKitErrorCode.notImplemented` from every engine until milestone 2.

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

await controller.play();           // prepares on demand (milestone 2)
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
- **`ReelVideoView`** renders frames with any `BoxFit`, `Alignment`,
  background color, clipping and border radius, plus optional poster,
  placeholder and error builders. No controls.

## Platform support

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Engine | Media3 1.11.1 ExoPlayer | AVPlayer | HTMLVideoElement |
| Rendering | `SurfaceProducer` texture | `FlutterTexture` | Platform view |
| Engine capabilities and adaptive pool size | Yes | Yes | Yes |
| Native player allocation, reuse, release | Yes | Yes (verified on simulator) | Yes |
| Source preparation and playback commands | Milestone 2 | Milestone 2 | Milestone 2 |
| HLS | Engine supports | Engine supports | Safari only (native) |
| DASH | Engine supports | No | No |
| Custom HTTP headers | Milestone 2 | Milestone 2 | Not possible with `<video>` |
| Disk cache | Milestone 6 | Milestone 6 | Browser cache only, no guarantees |
| `ReelSource.file` | Milestone 2 | Milestone 2 | Not available |
| `ReelSource.memory` | Not yet | Not yet | Not yet |

`ReelPlatformCapabilities` reports these flags at runtime, and never claims a
feature the engine does not provide.

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

Device integration tests:

```bash
cd packages/reelkit/example
flutter test integration_test -d <device-id>
```

## Roadmap

1. Foundation — **done**: workspace, federated plugin, public API, platform
   interface, Pigeon bridge, player pool, example, tests.
2. Single native player on each platform: sources, play/pause/seek/loop,
   events, first frame, rotation, errors.
3. Complete player API: tracks, metadata, source replacement, lifecycle.
4. Player manager: exclusive playback, decoder-failure-aware pool sizing.
5. Feed manager and intelligent preloading.
6. Cache, fullscreen and orientation coordination, audio sessions, retry.
7. Benchmarks, documentation, release.
