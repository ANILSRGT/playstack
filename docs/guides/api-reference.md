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
| `PlayStackDefaultControls`, `PlayStackHoldAction`, `PlayStackProgressBar`, `PlayStackBufferingIndicator`, `PlayStackMuteButton`, `PlayStackSubtitles`, `PlayStackSettingsSheet`, `PlayStackScreenLockOverlay`, `PlayStackErrorView` | Default feed controls and their parts | [Feeds](feed.md) |
| `PlayStackCinemaMode` | When a feed hides its controls by itself; the screen lock | [Feeds](feed.md#cinema-mode-and-screen-lock) |
| `PlayStackMediaSession`, `PlayStackMediaInfo`, `PlayStackPictureInPicture` | Lock screen and notification controls, background sound, Picture-in-Picture (`manager.mediaSession`, `manager.pictureInPicture`) | [Media controls and Picture-in-Picture](background-playback.md) |
| `PlayStackPreloadWindow`, `PlayStackFeedStats` | Applied window and feed counters | [Preloading](preloading.md) |
| `PlayStackPoolConfig`, `PlayStackPoolStats`, `PlayStackPlayerPriority` | Native player pool | [Manager](manager.md) |
| `PlayStackCacheConfig`, `PlayStackCacheManager`, `PlayStackCacheInfo` | Disk cache | [Caching](caching.md) |
| `PlayStackDownloads`, `PlayStackDownload`, `PlayStackDownloadState`, `PlayStackDownloadQuality` | Offline viewing, turned on per user (`manager.downloads`) | [Offline viewing](downloads.md) |
| `PlayStackFullscreenManager`, `PlayStackFullscreenConfig`, `PlayStackFullscreenOrientation` | Fullscreen and orientation | [Fullscreen](fullscreen.md) |
| `PlayStackAudioConfig`, `PlayStackAudioSessionCategory`, `PlayStackInterruption`, `PlayStackInterruptionType` | Audio focus, session and interruptions | [Audio](audio.md) |
| `PlayStackLifecycleConfig` | Background and foreground behavior | [Manager](manager.md) |
| `PlayStackTrack`, `PlayStackTrackType`, `PlayStackVideoQuality`, `PlayStackVideoQualityLimit` | Tracks, subtitles, the user's quality choice, quality caps | [Tracks and subtitles](subtitles.md) |
| `PlayStackVideoInfo`, `PlayStackPositionSnapshot`, `PlayStackPlayerMetrics` | Video properties, position, timings | [Controller](controller.md) |
| `PlayStackNetworkStatus`, `PlayStackNetworkType` | Connectivity | [Manager](manager.md) |
| `PlayStackPlatformCapabilities` | What the engine supports | [Platform support](platforms.md) |
| `PlayStackException`, `PlayStackErrorCode` | Errors | [Errors](errors.md) |
| `PlayStackAnalytics`, `PlayStackAnalyticsConfig`, `PlayStackAnalyticsEvent` and its subtypes | Typed playback events for analytics (`manager.analytics`, `PlayStackAnalytics.all`) | [Analytics](analytics.md) |
| `PlayStackSeries`, `PlayStackWatchProgress`, `PlayStackProgressStorage`, `PlayStackSkipMarker`, `PlayStackNextUp` | Continue watching, skip intro, next episode | [Series](series.md) |
| `PlayStackFeedCues`, `PlayStackCue`, `PlayStackCueController`, `PlayStackTransition` | Your own moments in a video and between items | [Cues and transitions](cues.md) |
| `PlayStackFeedAds`, `PlayStackAdBreak`, `PlayStackAdSource`, `PlayStackAd`, `PlayStackAdController`, `PlayStackAdOverlay`, `PlayStackVast`, `PlayStackAds` | VAST video ads | [Ads](ads.md) |
| `PlayStackDrm`, `PlayStackDrmType` | Widevine, PlayReady, ClearKey, FairPlay | [DRM](drm.md) |
| `PlayStackSubtitleSource`, `PlayStackSubtitleFormat` | Subtitle files | [Tracks and subtitles](subtitles.md#subtitle-files) |
| `PlayStackLiveBadge` | Live streams | [Live streams](live.md) |
| `PlayStackDragGestures`, `PlayStackThumbnails`, `PlayStackThumbnail`, `PlayStackScrubPreview`, `PlayStackDebugOverlay` | Gestures, scrub preview, debug panel | [Gestures](gestures.md) |
| `PlayStackSleepTimer` | Sleep timer (`manager.sleepTimer`); audio only is on the controller | [Sleep timer and audio only](sleep-timer.md) |
| `PlayStackAirPlayButton` | AirPlay; Chromecast is in `playstack_cast` | [Chromecast and AirPlay](cast.md) |

## Other packages

| Package | Role | Guide |
| --- | --- | --- |
| `playstack_cast` | `PlayStackCast`, `PlayStackCastButton`: Chromecast | [Chromecast and AirPlay](cast.md) |
| `playstack_test` | `FakePlayStackPlatform`, `pumpPlayStack`, `disposePlayStack`: tests without a device | [Testing](testing.md) |

## Engine implementers

`package:playstack_platform_interface` defines `PlayStackPlatform`, the
contract the Android, iOS and web engines implement. Applications do not
use it directly. A new engine extends `PlayStackPlatform` (never implements
it) and sets `PlayStackPlatform.instance` when registered; see
[Architecture](../ARCHITECTURE.md).
