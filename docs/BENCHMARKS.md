# Benchmarks

Measured with the example app's benchmark
(`packages/reelkit/example/lib/benchmark/reel_benchmark.dart`), which the
integration test `integration_test/benchmark_test.dart` and the example's
*Benchmark* page both run.

**Read these numbers as a baseline, not as device performance.** They come
from an emulator and a simulator on a desktop machine. Run the benchmark on
the phones you target before drawing conclusions; physical devices have
hardware decoders, slower storage and thermal limits that emulators do not
model.

## Method

- Media: a bundled 3 s, 1080x1920, 30 fps H.264 High-profile clip with
  AAC audio (`assets/videos/portrait_1080x1920.mp4`, 399 KB), so the
  network is excluded. Controllers are muted and looping; the disk cache is
  off.
- Timings are wall-clock times in Dart from the call to the moment the app
  can observe the result, including platform-channel round trips.
- A **start** is measured until the playback position has moved past zero,
  polled every 2 ms. Engines accept `play` within a few milliseconds, but
  the clock only starts once audio output is running, so "accepted" would
  understate what the user sees.
- Scenarios:
  - **First start:** `play()` on a new controller, including creation of
    the first native player.
  - **Cold start:** `play()` on an unprepared controller whose native
    player is reused from the pool (10 samples). *Preparation* and *time to
    first frame* come from `ReelPlayerController.metrics`.
  - **Preloaded start:** `play()` on a controller whose first frame was
    already rendered by `initialize()` (10 samples).
  - **Swipe:** a 21-item `ReelFeedManager` feed, 1.2 s on each item, then
    `setActiveIndex(next)`; measured until the new item's position moves.
  - **Rapid scroll:** `setActiveIndex` on 500 items, one change per frame
    (16 ms), with `maxPlayers: 3`; pool usage is sampled after every
    change.
  - **Memory:** resident set size (`ProcessInfo.currentRss`) after 10
    warm-up cycles and after 60 more cycles of creating a controller,
    preparing it to its first frame, disposing it and destroying the idle
    native player (`trimIdlePlayers`), so every cycle allocates and frees a
    native player and a 1080p decoder.

## Results (2026-11-10, ReelKit 0.1.0-dev.7)

Host: Apple M4 Pro, 24 GB, macOS 27.0.1.

| | Android 16 emulator (arm64, API 36), profile build | iOS 26.5 simulator (iPhone 17 Pro Max), debug build |
| --- | --- | --- |
| Engine | Media3 ExoPlayer 1.11.1 | AVFoundation AVPlayer |
| First start (creates the player) | 1065 ms | 508 ms |
| Cold start, median (p90) | 252 ms (270 ms) | 190 ms (192 ms) |
| Preparation, median | 127 ms | 88 ms |
| Preparation to first frame, median | 111 ms | 98 ms |
| Preloaded start, median (p90) | 126 ms (142 ms) | 98 ms (101 ms) |
| Swipe start, median (p90) | 106 ms (118 ms) | 150 ms (163 ms) |
| Swipe preload hit rate | 20 of 20 swipes | 20 of 20 swipes |
| Rapid scroll: peak native players (limit 3) | 3 | 2 |
| Rapid scroll: players created / leases reused | 3 / 497 | 2 / 498 |
| Rapid scroll: last item moving after the scroll stopped | 220 ms | 134 ms |
| Memory: RSS after warm-up, after 60 cycles | 219.7 MB, 219.9 MB (+0.2 MB) | 398.3 MB, 399.2 MB (+0.9 MB) |
| Memory: cycle duration | 118 ms | 34 ms |

On Android the first frame is rendered before the engine reports the
video ready, so *preparation to first frame* is shorter than
*preparation*.

The reported hit rate is 95% because the feed also counts the very first
activation, which nothing could have preloaded.

Across three runs on the same setup, memory growth over the 60 cycles was
+0.2, +5.9 and +0.2 MB on Android and +3.9, +0.2 and +0.9 MB on iOS: noise
of this size, not a per-cycle leak. A leaked 1080p decoder or surface would
add megabytes per cycle, hundreds of megabytes over the run.

### Web (headless Chromium)

Brave 157 (Chromium 157) in headless mode, driven by chromedriver, debug
build: the pool behaves as on mobile (rapid scroll: peak 3 of 3 players,
3 created, 496 reused; swipe hit rate 20 of 20), but the timings are not
comparable and are not a measure of browser performance. Headless
Chromium has no audio output, so its clock starts at once (preloaded
start 0 ms, cold start 10 ms median), and the same asset URL is served
from the browser's memory cache after the first load (preparation 1 ms).
Resident memory is not available on the web. Measure in a regular browser
window with network sources for meaningful web numbers.

## Observations

- **Preloading roughly halves the start on Android** (252 → 126 ms) and
  removes about 90 ms on iOS (190 → 98 ms). What remains, about 100 ms, is
  the engines starting audio output and their clock after `play`; it is
  the same for a video prepared seconds earlier. `metrics.lastStartLatency`
  and `ReelFeedStats.averageStartLatency` measure until the engine
  *accepts* `play` (1–5 ms for prepared videos), which is why this
  benchmark measures position instead.
- **The pool holds under abuse.** 500 index changes, one per frame, never
  exceeded the limit and created at most three native players; every other
  item reused one. Preparations of skipped items are cancelled, so the
  last item starts about as fast as a cold start once scrolling stops.
- **No preloads ran during the rapid scroll** (`preloads_cancelled: 0`):
  preloads start only after the active item is prepared, which never
  happened at one change per frame. This is the intended behavior; the
  active item gets all bandwidth and decoders.
- **The first native player is expensive** (about 0.5 s on iOS, 1.1 s on
  the Android emulator, where the first codec initialization in the
  process dominates). Initialize the manager and, if the first screen is a
  video, start preparing it as early as possible.

## Running it

On a physical device, in profile mode (Android supports profile builds on
arm64 emulators too; iOS simulators run debug only):

```bash
cd packages/reelkit/example
flutter drive --profile \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/benchmark_test.dart \
  -d <device-id>
```

The report is printed with a `[benchmark]` prefix and saved as JSON to
`build/integration_response_data.json`. Without a host, open the example
app's *Benchmark* page, run it and copy the JSON.

On the web, run the same target with `flutter drive -d web-server` (see
[Examples](guides/examples.md#on-the-web)).

The test asserts behavior only (pool bound, preloaded faster than cold,
swipe hit rate above 80%, memory growth below 32 MB); it has no timing
budget because timings depend on the device.
