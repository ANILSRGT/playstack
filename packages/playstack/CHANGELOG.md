## Unreleased

* `PlayStackFeedView<T>`: a complete feed screen in one widget. Pass `items`
  and `videoUrl` (and optionally `posterUrl` and `onLoadMore`). The view
  creates and releases its players and handles paging, vertical or
  horizontal swiping (`scrollDirection`, `reverse`), transitions, loading
  more, poster precaching, fullscreen and `autoAdvance` when a video ends.
  `controlsBuilder` and `videoBuilder` receive a typed `PlayStackFeedPage<T>`.
  `PlayStackFeedView.feed` shows a `PlayStackFeedManager` you manage yourself.
  `PlayStackFeedViewController` (a `Listenable`) moves pages, switches
  fullscreen and sound, and exposes the feed and the manager.
  Fullscreen opens on its own route above the app's bars, built with the
  same `controlsBuilder` (`page.isFullscreen` is true there). Turning the
  device sideways opens fullscreen and upright closes it
  (`fullscreenOnRotate`, on by default), also in an app locked to portrait.
* `PlayStackFullscreenManager.deviceOrientationChanges`: how the user holds
  the device, from the motion sensors (Android, iOS).
* Leaving fullscreen restores the orientations the app allowed before,
  read from the platform; `PlayStackConfig.reels()` no longer forces
  portrait (`appOrientations` sets a fixed list).
* `PlayStackConfig.reels()`, `PlayStackConfig.screenQualityLimit()` and
  `PlayStackFeedConfig.reels`: presets tuned for fast swiping, used by
  `PlayStackFeedView` by default.
* `PlayStackFeedTransition`: `slide`, `parallax`, `stack`, `fade`, `zoom`,
  `cube`, or `custom`. Transitions follow the finger and animate moves
  made from code.
* `PlayStackDefaultControls`: tap to pause, a feed-wide sound switch, a
  fullscreen button for landscape videos, a progress bar, a buffering indicator that appears only after a long wait, and
  retry. Its parts are public: `PlayStackProgressBar`, `PlayStackBufferingIndicator`
  and `PlayStackMuteButton`.
* `PlayStackFeedView` pauses while a route covers it or its tab is hidden
  (`pauseWhenHidden`), and `PlayStackFeedViewController.pause`/`resume` stop it
  under sheets and dialogs.
* `PlayStackFeedView.onItemViewed` reports each visit with a `PlayStackItemView`:
  watch time, duration, completion and the typed item.
* `PlayStackFeedView.onRefresh` turns on pull to refresh; off when null.
* Series support: `PlayStackFeedView.startPosition`, `PlayStackFeedItem.startPosition`,
  `PlayStackPlayerController.startPosition` and
  `PlayStackManager.createController(startPosition:)` prepare a video at a
  point; `PlayStackItemView.position` reports where the user left;
  `PlayStackFeedViewController.jumpToItem`, `animateToItem` and `indexOfItem`
  move to an item by your object.
* `PlayStackDefaultControls`: hold to pause or to play faster (`holdAction`,
  `PlayStackHoldAction`, `holdSpeed`), and a progress bar you can drag or tap
  to seek (`seekable`, `PlayStackProgressBar.seekable`, `touchHeight`).
* Pages without video: `videoUrl` or `source` may return null, and
  `PlayStackFeedView.pageBuilder` builds those pages (ads, cards). They take
  no player and are never preloaded. A list inside a page scrolls first and
  hands the swipe to the feed at its end. `PlayStackFeedItem.page`,
  `PlayStackFeedItem.isVideo`, `PlayStackFeedPage.cast`.
* Locked items: `PlayStackFeedView.isLocked` and `lockedBuilder`,
  `PlayStackFeedItem.locked`, `PlayStackFeedManager.setLocked`. Locked
  videos are never prepared or played.
* `PlayStackFeedPreload` and `PlayStackFeedView.preloaded` prepare a feed
  before its screen opens, for example on the splash screen.
* `PlayStackDefaultControls` shows subtitles and a settings button with
  playback speed and subtitle tracks; `PlayStackSubtitles` and
  `PlayStackSettingsSheet` are public.
* `PlayStackDefaultControls.child` sits above the gesture layer, so its buttons
  react at once instead of waiting for a possible double tap.
* `PlayStackConfig.reels(looping: false)`. With `autoAdvance` the view's own
  manager no longer loops.
* `PlayStackFeedItem` takes a `poster` and app `data`. `PlayStackFeedManager` gained
  `setMuted` and `muted` (feed-wide sound), `itemAt` and `manager`.

## 0.1.0-dev.7

* Licensed under the MIT license.
* Milestone 7: example benchmark (`lib/benchmark`, *Benchmark* page and
  `integration_test/benchmark_test.dart`) measuring cold, preloaded and
  swipe start latency until playback advances, rapid feed scrolling and
  memory across native player create/dispose cycles.
* `PlayStackPlayerMetrics.lastPreparationTime` is measured correctly when the
  engine renders the first frame before it reports the video ready (it
  equaled `lastTimeToFirstFrame` on Android).
* Integration tests run on the web (headless Chromium) and report per-test
  results, so a run in which no test executed fails.
* `setSource` cancels a pending automatic retry of the previous source
  instead of waiting for its delay.
* Every public member is documented (`public_member_api_docs`); guides for
  every feature in `docs/`.
* Package metadata (homepage, repository, issue tracker, topics) and
  aligned dependency constraints for publishing.

## 0.1.0-dev.6

* Milestone 6: disk cache (`PlayStackCacheConfig`, `PlayStackManager.cache`),
  fullscreen with orientation restoration (`PlayStackManager.fullscreen`,
  `PlayStackFullscreenConfig`), audio configuration (`PlayStackAudioConfig`) and
  `PlayStackPlayerController.interruptions`, automatic retry (`PlayStackRetryConfig`)
  plus `retry()` and `reinitialize()`, retry of offline failures on
  reconnection. `AsyncLock` keeps no future while idle (fixes a cross-zone
  deadlock on dispose).

## 0.1.0-dev.5

* Milestone 5: `PlayStackFeedManager` (`PlayStackManager.createFeed`) with a
  preload window bounded by network, memory and pool size, ordered preloads
  after the active item, cancellation on scroll, stable item ids
  (insert/remove/replaceAll/updateSource), pause/resume and `PlayStackFeedStats`.
  `PlayStackPlayerConfig.preloadBufferDuration`, `PlayStackManager.networkStatus`,
  `PlayStackPlayerController.metrics`. `release()` cancels a preparation in
  flight; cancelled preparations return to `idle` instead of `error`.

## 0.1.0-dev.4

* Milestone 4: exclusive playback (`PlayStackConfig.exclusivePlayback`,
  `PlayStackManager.activeController`), pool limit lowered and preparation
  retried once when a decoder cannot be allocated
  (`PlayStackPoolConfig.adaptToDecoderFailures`), memory pressure releases
  `background` controllers, per-priority pool stats. Fixes a lease leak when
  a controller was disposed while its native player was being created.

## 0.1.0-dev.3

* Milestone 3: audio/video/subtitle tracks with subtitle text events, video
  quality limits, metadata (frame rate, bitrate, codec, live), `setSource`,
  `stop`, `positions()` stream, app lifecycle pause/resume.

## 0.1.0-dev.2

* Milestone 2: native playback (sources, play/pause/seek/loop, volume, speed,
  first frame, rotation, typed errors), `clearSource` for idle pooled players.

## 0.1.0-dev.1

* Milestone 1 foundation. Development preview; see the repository README for status.
