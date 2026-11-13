# reelkit

Short-video feeds and native video playback for Flutter. Put a
Reels/Shorts/TikTok-style feed on screen with one widget, or drive single
players yourself. ReelKit handles the native players, preloading,
memory, network and lifecycle.

Engines: AndroidX Media3 ExoPlayer (Android), AVFoundation (iOS) and
`HTMLVideoElement` (web).

## Features

- **One-widget feed.** `ReelFeedView` takes your items and does the rest:
  paging, playing the video in view, preparing the next ones, loading
  more, posters, fullscreen.
- **Instant swipes.** A bounded pool of native players reused by
  priority. The next videos are prepared ahead within network, memory and
  decoder limits, and stale preparations are cancelled when the user
  swipes fast.
- **Replaceable controls.** Default controls (tap or hold to pause, sound,
  fullscreen, a seekable progress bar, buffering, retry), your own layer
  on top, or your own controls from reusable parts.
- **Transitions and direction.** Slide, parallax, stack, fade, zoom, cube
  or your own; vertical or horizontal, normal or reversed.
- **App-aware.** Pauses under pushed routes, in hidden tabs and in the
  background. Pull to refresh and watch-time reports are one callback
  each.
- **Disk cache, fullscreen with orientation restore, audio focus and
  interruptions, automatic retry, tracks and subtitles, typed errors.**

## Install

```bash
flutter pub add reelkit
```

| | Minimum |
| --- | --- |
| Flutter / Dart | 3.47 / 3.13 |
| Android | API 24 |
| iOS | 15.0 |

No platform setup is needed for HTTPS videos. For `http://` URLs, HLS in
non-Safari browsers and the iOS silent switch, see
[Installation](https://github.com/ANILSRGT/reelkit/blob/main/docs/guides/installation.md).

## A feed in one widget

```dart
import 'package:reelkit/reelkit.dart';

ReelFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  posterUrl: (post) => post.thumbnailUrl,  // optional: shown until the first frame
  onLoadMore: () => api.fetchMorePosts(),  // optional: return [] at the end
)
```

A list of URL strings needs nothing else: `ReelFeedView(items: urls)`.

### Your UI on top

`controlsBuilder` gets each page, with your item typed as `page.data`:

```dart
ReelFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  controlsBuilder: (context, page) => ReelDefaultControls(
    page: page,
    onDoubleTap: () => like(page.data),
    child: PostCaption(post: page.data),   // your caption, buttons, avatar
  ),
)
```

Replace the defaults completely with your own widget; `ReelProgressBar`,
`ReelBufferingIndicator` and `ReelMuteButton` are there to reuse.

### Everything else is optional

```dart
ReelFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  transition: ReelFeedTransition.stack,         // slide, parallax, stack, fade, zoom, cube, custom
  scrollDirection: Axis.horizontal,             // stories, carousels
  onRefresh: () => api.fetchPosts(page: 0),     // pull to refresh; off when null
  onItemViewed: (view) => analytics.watched(    // called when the user leaves a video
    view.data.id, view.watchTime, view.completed,
  ),
  controller: viewController,                   // nextPage, jumpToItem, fullscreen, mute, pause
)
```

### Series

The same widget plays a series: open it at an episode, continue where the
user stopped and move on when an episode ends.

```dart
ReelFeedView<Episode>(
  items: series.episodes,
  videoUrl: (episode) => episode.url,
  initialIndex: series.episodes.indexOf(tapped),
  startPosition: (episode) => progress[episode.id],           // continue watching
  onItemViewed: (view) => progress[view.data.id] = view.position,
  autoAdvance: true,                                          // next episode
)

viewController.jumpToItem(series.episodes[7]);               // episode list
```

## A single player

```dart
final manager = ReelKitManager();
await manager.initialize();
final controller = manager.createController(
  ReelSource.network('https://example.com/video.m3u8'),
);

ReelVideoView(controller: controller, fit: BoxFit.cover);  // frames only, no controls
await controller.play();                                   // prepares on demand

await manager.dispose();                                   // releases every player
```

`ReelPlayerController` is a `ValueListenable<ReelPlaybackState>`: build
your controls from it.

## Platform support

| | Android | iOS | Web |
| --- | --- | --- | --- |
| HLS / DASH | Yes / Yes | Yes / No | Safari or HLS.js / No |
| Network, asset, memory sources | Yes | Yes | Yes (no custom headers) |
| File sources | Yes | Yes | No |
| Disk cache | Progressive + HLS/DASH segments | Progressive | Browser cache |
| Fullscreen and orientation | Yes | Yes | Fullscreen API |

[Full matrix](https://github.com/ANILSRGT/reelkit/blob/main/docs/guides/platforms.md).
`ReelPlatformCapabilities` reports what the running engine supports.

## Learn more

- [Guides](https://github.com/ANILSRGT/reelkit/blob/main/docs/README.md):
  feeds, controller, manager, preloading, caching, fullscreen, audio,
  subtitles, errors, performance
- [Demo app](https://github.com/ANILSRGT/reelkit/tree/main/demo): a reels
  app (likes, comments, explore grid, live stats) and a drama app
  (episodes, continue watching, episode list)
- [Benchmarks](https://github.com/ANILSRGT/reelkit/blob/main/docs/BENCHMARKS.md)
- [Issues](https://github.com/ANILSRGT/reelkit/issues)

Development preview: verified on an Android emulator, an iOS simulator
and headless Chromium; not yet on physical devices.
