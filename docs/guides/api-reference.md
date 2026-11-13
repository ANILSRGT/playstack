# API reference

The full reference is generated from the source documentation with
`dart doc` (and on pub.dev once the packages are published):

```bash
cd packages/playstack
dart doc --output build/api
open build/api/index.html
```

Every public member is documented; the `public_member_api_docs` lint keeps
it that way.

## Main types

Library: `package:playstack/playstack.dart` (re-exports the types of
`playstack_platform_interface` that applications use).

| Type | Role | Guide |
| --- | --- | --- |
| `PlayStackManager` | Engine, pool, controllers, feeds, cache, fullscreen, network status | [Manager](manager.md) |
| `PlayStackConfig` | `pool`, `player`, `lifecycle`, `exclusivePlayback`, `cache`, `audio`, `fullscreen` | [Manager](manager.md) |
| `PlayStackPlayerController` | One video: play, pause, seek, settings, tracks, position, retry | [Controller](controller.md) |
| `PlayStackPlayerConfig`, `PlayStackRetryConfig` | Controller defaults and automatic retry | [Errors](errors.md) |
| `PlayStackPlaybackState`, `PlayStackPlaybackStatus` | Observable controller state | [Controller](controller.md) |
| `PlayStackSource` (`network`, `asset`, `file`, `memory`), `PlayStackCachePolicy` | What to play | [Controller](controller.md) |
| `PlayStackVideoView` | Renders frames with `fit`, `alignment`, poster, placeholder and error builders | [Rendering](rendering.md) |
| `PlayStackFeedManager`, `PlayStackFeedItem`, `PlayStackFeedConfig`, `PlayStackNetworkPreloadPolicy` | Feeds and preloading | [Feeds](feed.md), [Preloading](preloading.md) |
| `PlayStackFeedView`, `PlayStackFeedPage`, `PlayStackFeedViewController`, `PlayStackFeedTransition` | Complete feed screen from a list of items: players, paging, loading more, pull to refresh, pausing when hidden, direction, transitions, fullscreen, builders | [Feeds](feed.md) |
| `PlayStackFeedPreload` | A feed prepared before its screen opens, shown with `PlayStackFeedView.preloaded` | [Feeds](feed.md#preparing-before-the-screen-opens) |
| `PlayStackFeedItemBuilder` | Builds pages without video and locked items (`pageBuilder`, `lockedBuilder`) | [Feeds](feed.md#pages-without-video) |
| `PlayStackItemView` | Watch time and position of one visit, from `PlayStackFeedView.onItemViewed` | [Feeds](feed.md#watch-time) |
| `PlayStackConfig.reels`, `PlayStackFeedConfig.reels` | Presets tuned for fast swiping | [Feeds](feed.md) |
| `PlayStackDefaultControls`, `PlayStackHoldAction`, `PlayStackProgressBar`, `PlayStackBufferingIndicator`, `PlayStackMuteButton`, `PlayStackSubtitles`, `PlayStackSettingsSheet` | Default feed controls and their parts | [Feeds](feed.md) |
| `PlayStackPreloadWindow`, `PlayStackFeedStats` | Applied window and feed counters | [Preloading](preloading.md) |
| `PlayStackPoolConfig`, `PlayStackPoolStats`, `PlayStackPlayerPriority` | Native player pool | [Manager](manager.md) |
| `PlayStackCacheConfig`, `PlayStackCacheManager`, `PlayStackCacheInfo` | Disk cache | [Caching](caching.md) |
| `PlayStackFullscreenManager`, `PlayStackFullscreenConfig`, `PlayStackFullscreenOrientation` | Fullscreen and orientation | [Fullscreen](fullscreen.md) |
| `PlayStackAudioConfig`, `PlayStackAudioSessionCategory`, `PlayStackInterruption`, `PlayStackInterruptionType` | Audio focus, session and interruptions | [Audio](audio.md) |
| `PlayStackLifecycleConfig` | Background and foreground behavior | [Manager](manager.md) |
| `PlayStackTrack`, `PlayStackTrackType`, `PlayStackVideoQualityLimit` | Tracks, subtitles, quality caps | [Tracks and subtitles](subtitles.md) |
| `PlayStackVideoInfo`, `PlayStackPositionSnapshot`, `PlayStackPlayerMetrics` | Video properties, position, timings | [Controller](controller.md) |
| `PlayStackNetworkStatus`, `PlayStackNetworkType` | Connectivity | [Manager](manager.md) |
| `PlayStackPlatformCapabilities` | What the engine supports | [Platform support](platforms.md) |
| `PlayStackException`, `PlayStackErrorCode` | Errors | [Errors](errors.md) |

## Engine implementers

`package:playstack_platform_interface` defines `PlayStackPlatform`, the
contract the Android, iOS and web engines implement. Applications do not
use it directly. A new engine extends `PlayStackPlatform` (never implements
it) and sets `PlayStackPlatform.instance` when registered; see
[Architecture](../ARCHITECTURE.md).
