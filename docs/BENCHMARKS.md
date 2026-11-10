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
| First start (creates the player) | 1168 ms | 345 ms |
| Cold start, median (p90) | 270 ms (329 ms) | 190 ms (192 ms) |
| Preparation, median | 117 ms | 87 ms |
| Preparation to first frame, median | 117 ms | 101 ms |
| Preloaded start, median (p90) | 122 ms (144 ms) | 102 ms (104 ms) |
| Swipe start, median (p90) | 109 ms (128 ms) | 151 ms (154 ms) |
| Swipe preload hit rate | 20 of 20 swipes | 20 of 20 swipes |
| Rapid scroll: peak native players (limit 3) | 3 | 2 |
| Rapid scroll: players created / leases reused | 3 / 497 | 2 / 498 |
| Rapid scroll: last item moving after the scroll stopped | 165 ms | 126 ms |
| Memory: RSS after warm-up, after 60 cycles | 218.7 MB, 224.6 MB (+5.9 MB) | 422.5 MB, 422.7 MB (+0.2 MB) |
| Memory: cycle duration | 113 ms | 34 ms |

The reported hit rate is 95% because the feed also counts the very first
activation, which nothing could have preloaded.

An earlier run on the same setup measured +0.2 MB (Android) and +3.9 MB
(iOS) across the memory cycles, so the growth is noise of this size, not a
per-cycle leak: a leaked 1080p decoder or surface would add megabytes per
cycle, hundreds of megabytes over the run.

## Observations

- **Preloading roughly halves the start on Android** (270 → 122 ms) and
  removes 90 ms on iOS (190 → 102 ms). What remains, about 100 ms, is the
  engines starting audio output and their clock after `play`; it is the
  same for a video prepared seconds earlier. `metrics.lastStartLatency` and
  `ReelFeedStats.averageStartLatency` measure until the engine *accepts*
  `play` (1–5 ms for prepared videos), which is why this benchmark measures
  position instead.
- **The pool holds under abuse.** 500 index changes, one per frame, never
  exceeded the limit and created at most three native players; every other
  item reused one. Preparations of skipped items are cancelled, so the
  last item starts about as fast as a cold start once scrolling stops.
- **No preloads ran during the rapid scroll** (`preloads_cancelled: 0`):
  preloads start only after the active item is prepared, which never
  happened at one change per frame. This is the intended behavior; the
  active item gets all bandwidth and decoders.
- **The first native player is expensive** (345 ms on iOS, 1.2 s on the
  Android emulator, where the first codec initialization in the process
  dominates). Initialize the manager and, if the first screen is a video,
  start preparing it as early as possible.

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

The test asserts behavior only (pool bound, preloaded faster than cold,
swipe hit rate above 80%, memory growth below 32 MB); it has no timing
budget because timings depend on the device.
