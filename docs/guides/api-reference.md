# API reference

The full reference is generated from the source documentation with
`dart doc` (and on pub.dev once the packages are published):

```bash
cd packages/reelkit
dart doc --output build/api
open build/api/index.html
```

Every public member is documented; the `public_member_api_docs` lint keeps
it that way.

## Main types

Library: `package:reelkit/reelkit.dart` (re-exports the types of
`reelkit_platform_interface` that applications use).

| Type | Role | Guide |
| --- | --- | --- |
| `ReelKitManager` | Engine, pool, controllers, feeds, cache, fullscreen, network status | [Manager](manager.md) |
| `ReelKitConfig` | `pool`, `player`, `lifecycle`, `exclusivePlayback`, `cache`, `audio`, `fullscreen` | [Manager](manager.md) |
| `ReelPlayerController` | One video: play, pause, seek, settings, tracks, position, retry | [Controller](controller.md) |
| `ReelPlayerConfig`, `ReelRetryConfig` | Controller defaults and automatic retry | [Errors](errors.md) |
| `ReelPlaybackState`, `ReelPlaybackStatus` | Observable controller state | [Controller](controller.md) |
| `ReelSource` (`network`, `asset`, `file`, `memory`), `ReelCachePolicy` | What to play | [Controller](controller.md) |
| `ReelVideoView` | Renders frames with `fit`, `alignment`, poster, placeholder and error builders | [Rendering](rendering.md) |
| `ReelFeedManager`, `ReelFeedItem`, `ReelFeedConfig`, `ReelNetworkPreloadPolicy` | Feeds and preloading | [Feeds](feed.md), [Preloading](preloading.md) |
| `ReelFeedView`, `ReelFeedPage`, `ReelFeedViewController`, `ReelFeedTransition` | Feed screen: paging, direction, transitions, builders | [Feeds](feed.md) |
| `ReelDefaultControls`, `ReelProgressBar`, `ReelBufferingIndicator`, `ReelMuteButton` | Default feed controls and their parts | [Feeds](feed.md) |
| `ReelPreloadWindow`, `ReelFeedStats` | Applied window and feed counters | [Preloading](preloading.md) |
| `ReelPoolConfig`, `ReelPoolStats`, `ReelPlayerPriority` | Native player pool | [Manager](manager.md) |
| `ReelCacheConfig`, `ReelCacheManager`, `ReelCacheInfo` | Disk cache | [Caching](caching.md) |
| `ReelFullscreenManager`, `ReelFullscreenConfig`, `ReelFullscreenOrientation` | Fullscreen and orientation | [Fullscreen](fullscreen.md) |
| `ReelAudioConfig`, `ReelAudioSessionCategory`, `ReelInterruption`, `ReelInterruptionType` | Audio focus, session and interruptions | [Audio](audio.md) |
| `ReelLifecycleConfig` | Background and foreground behavior | [Manager](manager.md) |
| `ReelTrack`, `ReelTrackType`, `ReelVideoQualityLimit` | Tracks, subtitles, quality caps | [Tracks and subtitles](subtitles.md) |
| `ReelVideoInfo`, `ReelPositionSnapshot`, `ReelPlayerMetrics` | Video properties, position, timings | [Controller](controller.md) |
| `ReelNetworkStatus`, `ReelNetworkType` | Connectivity | [Manager](manager.md) |
| `ReelPlatformCapabilities` | What the engine supports | [Platform support](platforms.md) |
| `ReelKitException`, `ReelKitErrorCode` | Errors | [Errors](errors.md) |

## Engine implementers

`package:reelkit_platform_interface` defines `ReelKitPlatform`, the
contract the Android, iOS and web engines implement. Applications do not
use it directly. A new engine extends `ReelKitPlatform` (never implements
it) and sets `ReelKitPlatform.instance` when registered; see
[Architecture](../ARCHITECTURE.md).
