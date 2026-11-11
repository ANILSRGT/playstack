## Unreleased

* `ReelFeedView<T>`: a complete feed screen in one widget. Pass `items`
  and `videoUrl` (and optionally `posterUrl` and `onLoadMore`). The view
  creates and releases its players and handles paging, vertical or
  horizontal swiping (`scrollDirection`, `reverse`), transitions, loading
  more, poster precaching, fullscreen and `autoAdvance` when a video ends.
  `controlsBuilder` and `videoBuilder` receive a typed `ReelFeedPage<T>`.
  `ReelFeedView.feed` shows a `ReelFeedManager` you manage yourself.
  `ReelFeedViewController` (a `Listenable`) moves pages, switches
  fullscreen and sound, and exposes the feed and the manager.
* `ReelKitConfig.reels()`, `ReelKitConfig.screenQualityLimit()` and
  `ReelFeedConfig.reels`: presets tuned for fast swiping, used by
  `ReelFeedView` by default.
* `ReelFeedTransition`: `slide`, `parallax`, `stack`, `fade`, `zoom`,
  `cube`, or `custom`. Transitions follow the finger and animate moves
  made from code.
* `ReelDefaultControls`: tap to pause, a feed-wide sound switch, a
  fullscreen button for landscape videos, a progress bar, a buffering indicator that appears only after a long wait, and
  retry. Its parts are public: `ReelProgressBar`, `ReelBufferingIndicator`
  and `ReelMuteButton`.
* `ReelFeedItem` takes a `poster` and app `data`. `ReelFeedManager` gained
  `setMuted` and `muted` (feed-wide sound), `itemAt` and `manager`.

## 0.1.0-dev.7

* Licensed under the MIT license.
* Milestone 7: example benchmark (`lib/benchmark`, *Benchmark* page and
  `integration_test/benchmark_test.dart`) measuring cold, preloaded and
  swipe start latency until playback advances, rapid feed scrolling and
  memory across native player create/dispose cycles.
* `ReelPlayerMetrics.lastPreparationTime` is measured correctly when the
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

* Milestone 6: disk cache (`ReelCacheConfig`, `ReelKitManager.cache`),
  fullscreen with orientation restoration (`ReelKitManager.fullscreen`,
  `ReelFullscreenConfig`), audio configuration (`ReelAudioConfig`) and
  `ReelPlayerController.interruptions`, automatic retry (`ReelRetryConfig`)
  plus `retry()` and `reinitialize()`, retry of offline failures on
  reconnection. `AsyncLock` keeps no future while idle (fixes a cross-zone
  deadlock on dispose).

## 0.1.0-dev.5

* Milestone 5: `ReelFeedManager` (`ReelKitManager.createFeed`) with a
  preload window bounded by network, memory and pool size, ordered preloads
  after the active item, cancellation on scroll, stable item ids
  (insert/remove/replaceAll/updateSource), pause/resume and `ReelFeedStats`.
  `ReelPlayerConfig.preloadBufferDuration`, `ReelKitManager.networkStatus`,
  `ReelPlayerController.metrics`. `release()` cancels a preparation in
  flight; cancelled preparations return to `idle` instead of `error`.

## 0.1.0-dev.4

* Milestone 4: exclusive playback (`ReelKitConfig.exclusivePlayback`,
  `ReelKitManager.activeController`), pool limit lowered and preparation
  retried once when a decoder cannot be allocated
  (`ReelPoolConfig.adaptToDecoderFailures`), memory pressure releases
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
