# PlayStack

PlayStack is a video playback manager for Flutter, built for fast-scrolling video
feeds and for single players. It handles native players, pooling, preloading,
lifecycle and errors. A complete reels feed is one widget with replaceable
controls; for anything else you build the UI on its players.

> **Status: 0.1.0-dev.7, development preview (milestone 7 of 7).**
> Playback, pooling, feeds with preloading, disk cache, fullscreen, audio
> handling and retry work on Android (Media3), iOS (AVPlayer) and web
> (`<video>`), verified on an Android emulator, an iOS simulator and
> headless Chromium. Not yet verified on physical devices. See [what was verified where](docs/guides/platforms.md#what-was-verified-where).

## Packages

| Package | Description |
| --- | --- |
| [`playstack`](packages/playstack) | The package applications depend on. |
| [`playstack_platform_interface`](packages/playstack_platform_interface) | Contract shared by the engines. |
| [`playstack_android`](packages/playstack_android) | Media3 ExoPlayer engine. |
| [`playstack_ios`](packages/playstack_ios) | AVFoundation engine. |
| [`playstack_web`](packages/playstack_web) | `HTMLVideoElement` engine. |

Documentation: [guides](docs/README.md) (installation, quick start,
controller, manager, feeds, preloading, caching, fullscreen, rendering,
audio, subtitles, errors, platform support, performance, API reference,
examples), [architecture](docs/ARCHITECTURE.md) and
[benchmarks](docs/BENCHMARKS.md).

Try it: [`demo/`](demo) holds two small apps behind one launcher: reels
(endless feed, pull to refresh, likes, comments, an explore grid, watch
time and live stats) and drama (a series in episodes: continue watching,
jump to any episode, next episode on its own) — `cd demo && flutter run`.

## Quick start

```dart
import 'package:playstack/playstack.dart';

final manager = PlayStackManager(
  config: const PlayStackConfig(
    pool: PlayStackPoolConfig(maxPlayers: 3), // omit for a device-adaptive limit
    player: PlayStackPlayerConfig(looping: true),
  ),
);
await manager.initialize();

final controller = manager.createController(
  PlayStackSource.network(
    'https://example.com/video.mp4',
    headers: {'Authorization': 'Bearer <token>'},
  ),
);

// Your UI: PlayStack only renders frames.
Stack(
  fit: StackFit.expand,
  children: [
    PlayStackVideoView(
      controller: controller,
      fit: BoxFit.cover,
      poster: const NetworkImage('https://example.com/poster.jpg'),
      errorBuilder: (context, error) => Center(child: Text(error.message)),
    ),
    // your buttons, progress bar, overlays...
  ],
);

await controller.play();           // prepares on demand
await controller.setSource(PlayStackSource.asset('assets/next.mp4')); // same player
controller.positions().listen(print); // polls only while playing
await controller.release();        // give the native player back, keep controller
await manager.dispose();           // releases every controller and player
```

### Feeds

A complete reels screen is one widget:

```dart
PlayStackFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  posterUrl: (post) => post.thumbnailUrl,  // optional
  onLoadMore: () => api.fetchMorePosts(),  // optional; return [] at the end
)
```

The widget creates and releases the players, plays the video in view,
prepares the next ones and loads more items. It pauses under pushed
routes, in hidden tabs and in the background. It also shows default
controls: tap or hold to pause, sound, fullscreen for landscape videos, a
progress bar you can drag, and retry. A list of URLs needs nothing else:
`PlayStackFeedView(items: urls)`.

Customize only what you need:

```dart
PlayStackFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  transition: PlayStackFeedTransition.stack,  // slide, parallax, stack, fade, zoom, cube
  scrollDirection: Axis.horizontal,      // stories, carousels
  onRefresh: () => api.fetchPosts(page: 0),       // pull to refresh; off when null
  onItemViewed: (view) => log(view.watchTime),    // when the user leaves a video
  controlsBuilder: (context, page) => PlayStackDefaultControls(
    page: page,
    child: MyCaption(post: page.data),   // page.data is your Post
  ),
)
```

## Concepts

- **`PlayStackManager`** owns the engine, the native player pool and its
  controllers. Use one per playback context, for example one per feed.
- **`PlayStackPlayerController`** controls one video. Creating it allocates
  nothing native; it leases a native player when initialized or played and
  returns it on `dispose`. Observe it as a
  `ValueListenable<PlayStackPlaybackState>`.
- **Pool.** At most `maxPlayers` native players exist. A controller with
  higher `priority` (`background < preload < visible < active`) can take the
  player of a lower one; that controller returns to `idle` and prepares again
  on its next `initialize` or `play`.
- **Exclusive playback.** By default only one controller of a manager plays:
  `play` pauses the others, and when several `play` calls overlap the most
  recent one wins. `manager.activeController` tells which controller is
  playing. Set `PlayStackConfig(exclusivePlayback: false)` to play several
  videos at once (for example a muted preview grid).
- **Decoder shortage.** Hardware decoders are shared with other apps, so the
  number a device sustains is only known at run time. When a video fails with
  `decoderUnavailable` while other players of the pool hold videos, the pool
  limit drops to that number and the video is retried once on a player taken
  from a lower-priority controller (`PlayStackPoolConfig.adaptToDecoderFailures`).
  `poolStats.decoderLimitReductions` counts these events.
- **Memory pressure** destroys idle native players and releases the players
  of `background` controllers.
- **Feeds.** `PlayStackFeedManager` (from `manager.createFeed`) works with any
  scrolling widget: report the item in view with `setActiveIndex`. It plays
  that item and prepares the window around it, next item first, once the
  active item is prepared (or after `activeHeadStart`, 300 ms),
  `maxConcurrentPreloads` at a time. `startupQualityLimit` prepares
  adaptive streams at a low rendition and switches up when playing, for
  feeds swiped several times a second. Items that
  leave the window give their player back at once, cancelling preparations
  in flight, so fast scrolling does not queue work. Items are identified by
  id across `insert`, `removeAt`, `replaceAll` and `updateSource`.
  `feed.stats` reports the preload hit rate and start latency.
- **Preload limits.** The window shrinks on metered networks (1 ahead),
  with data saver (none), offline (network items are not preloaded), on
  low-RAM devices, for 30 s after a memory warning, and to `maxPlayers - 1`
  (items behind give way first). Prepared-ahead videos buffer only
  `PlayStackPlayerConfig.preloadBufferDuration` (5 s) until they play.
  `manager.networkStatus` exposes the connectivity the engine reports; an
  active item that failed for lack of network restarts on reconnection.
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
  (`PlayStackLifecycleConfig`). `manager.pauseAll()` pauses everything.
  `PlayStackFeedView` also pauses itself under pushed routes and in hidden
  tabs.
- **Disk cache.** `PlayStackCacheConfig` (on by default, 256 MB, LRU) keeps
  downloaded video on disk, so replays, scrolling back and preloaded items
  that become active do not download again. Android caches progressive
  files and HLS/DASH segments (manifests are always fetched fresh); iOS
  caches progressive files through an `AVAssetResourceLoader` (HLS is not
  cached on iOS). `manager.cache` reports usage and clears or removes
  entries; `PlayStackNetworkSource(cacheKey: ...)` keeps signed URLs on one entry
  and `cachePolicy: PlayStackCachePolicy.bypass` keeps private content off disk.
  Browsers use their own HTTP cache, which PlayStack does not control.
- **Fullscreen.** PlayStack does not build a fullscreen screen; you show your
  own and call `manager.fullscreen.enter(...)` / `exit()`. By default the
  orientation is left alone (`keepCurrent`); `landscape`, `portrait` and
  `matchVideo` lock it while fullscreen. On exit the system bars return, the
  interface rotates back to where it was, and the policy from
  `PlayStackFullscreenConfig` (or `setAppPolicy`, if your app changes it per
  route) is restored, because Flutter cannot read the app's previous
  policy. On web the Fullscreen API needs a user gesture (`notAllowed`
  otherwise) and orientation locking works only where the browser allows it.
- **Audio.** `PlayStackAudioConfig`: on Android audible players take audio focus
  and pause when another app takes it, muted players never take focus, and
  unplugging headphones pauses. On iOS the audio session is left to the app
  unless `iosAudioSessionCategory` is set (`playback` plays with the silent
  switch on); interruptions (calls, alarms) pause and, with
  `resumeAfterInterruption`, resume. `controller.interruptions` tells the
  app why playback stopped.
- **Retry.** `PlayStackRetryConfig` (2 retries, 1 s then 2 s) retries network
  errors and timeouts: a failed preparation inside the same `initialize` /
  `play` call, a failure during playback by preparing again at the same
  position and resuming. `retry()` and `reinitialize()` do it on demand, and
  controllers that failed offline retry when the network returns.
- **`PlayStackVideoView`** renders frames with any `BoxFit`, `Alignment`,
  background color, clipping and border radius, plus optional poster,
  placeholder and error builders. No controls. On web, show a controller in
  one view at a time (one `<video>` element).
- **`PlayStackFeedView`** is a complete feed screen: give it your items. It
  owns the players and handles paging, vertical or horizontal swiping,
  transitions, posters, loading more and fullscreen. It shows
  `PlayStackDefaultControls` unless you pass your own `controlsBuilder`. Its
  defaults (`PlayStackConfig.reels`, `PlayStackFeedConfig.reels`) are tuned for
  fast swiping.

Each concept has a guide with examples in [docs/](docs/README.md).

## Platform support

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Engine | Media3 1.11.1 ExoPlayer (API 24+) | AVPlayer (iOS 15+) | HTMLVideoElement |
| Network, asset, memory sources | Yes | Yes | Yes (no custom headers) |
| File sources | Yes | Yes | No |
| HLS / DASH | Yes / Yes | Yes / No | Safari or HLS.js / No |
| Tracks and subtitles | Yes | Yes (no rendition choice) | What the browser exposes |
| Disk cache | Progressive + HLS/DASH segments | Progressive | Browser cache only |
| Preload buffer limit | Yes | Preference | No |
| Fullscreen and orientation | Yes | Yes | Fullscreen API (user gesture) |
| Audio focus / session | Audio focus | `AVAudioSession` category, interruptions | Browser |

The complete matrix, with every limitation and the error each one raises:
[docs/guides/platforms.md](docs/guides/platforms.md).
`PlayStackPlatformCapabilities` reports these flags at runtime and never claims
a feature the engine does not provide.

Verified: the integration suite in `packages/playstack/example/integration_test`
(including the benchmark) passes on an Android 16 emulator (API 36), an
iOS 26.5 simulator and headless Chromium 157 (web skips the tests that need
a local `dart:io` server or device orientation). The decoder-shortage retry
and audio interruptions are covered by unit tests only; HLS.js has not
been run in a browser. Baseline measurements: [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Errors

Every failure is a `PlayStackException` with a `PlayStackErrorCode`
(`network`, `decoder`, `decoderUnavailable`, `sourceNotFound`, `poolExhausted`, `timeout`,
`notImplemented`, ...). Preparation errors are also exposed in
`controller.value.error`. See [Errors and retry](docs/guides/errors.md).

## Development

Requirements: Flutter 3.47+ (developed on 3.47.4), Dart 3.13+, JDK 17,
Xcode with iOS 15+ SDK.

```bash
flutter pub get                      # resolves the whole workspace
flutter analyze
flutter test packages/playstack/test packages/playstack_platform_interface/test \
  packages/playstack_android/test packages/playstack_ios/test
./tool/generate_pigeons.sh           # after editing pigeons/playstack_messages.dart
```

Adding Swift files to `playstack_ios` requires `pod install` in the example's
`ios` folder (CocoaPods snapshots the file list).

Device integration tests and the benchmark:

```bash
cd packages/playstack/example
flutter test integration_test -d <device-id>
flutter drive --profile --driver=test_driver/integration_test.dart \
  --target=integration_test/benchmark_test.dart -d <device-id>
```

Releasing: [docs/RELEASING.md](docs/RELEASING.md).

## Roadmap

1. Foundation — **done**: workspace, federated plugin, public API, platform
   interface, Pigeon bridge, player pool, example, tests.
2. Single native player — **done**: sources, play/pause/seek/loop, volume,
   speed, events, first frame, rotation, typed errors on all platforms.
3. Complete player API — **done**: tracks and subtitles, quality limits,
   metadata, source replacement, stop, position stream, app lifecycle.
4. Player manager — **done**: exclusive playback and active controller,
   decoder-shortage pool sizing with retry, memory-pressure release,
   per-priority pool stats.
5. Feed manager and preloading — **done**: `PlayStackFeedManager`, preload window
   bounded by network, memory and pool, preload cancellation, buffer limits
   for prepared-ahead videos, network status, start-latency metrics.
6. Advanced features — **done**: disk cache (Android, iOS), fullscreen with
   orientation restoration, audio focus/session and interruptions,
   automatic and manual retry, cache bypass per source, HLS.js on the web.
7. Optimization and release — **done**: benchmark (start latency,
   preloading, rapid scrolling, memory) in the example app and as an
   integration test, documentation guides for every feature, documented
   public API, release checklist, web suite run in a browser. Publishing
   waits for physical-device verification.

## License

MIT. See [LICENSE](LICENSE).
