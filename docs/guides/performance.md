# Performance tuning

Measure first: run the example's benchmark on the devices you target (see
[Benchmarks](../BENCHMARKS.md)) and watch `manager.poolStats` and
`feed.stats` while you change settings. Debug builds are much slower in
Dart; measure profile or release builds.

## Start latency

| Lever | Effect |
| --- | --- |
| Preload (`ReelFeedConfig.preloadAhead`, or `initialize()` ahead of time) | Removes preparation from the start: about half of the start on the benchmark devices. The remaining ~100 ms is the engine starting audio output and its clock. |
| `maxConcurrentPreloads: 1` (default) | The next item is ready soonest; more parallel preloads split bandwidth and decoders. For fast swiping, raise it together with `preloadAhead` and `startupQualityLimit`; see [Preloading](preloading.md#fast-swiping). |
| `ReelPlayerConfig.videoQualityLimit` | Caps renditions to the view's size in physical pixels; avoids stalls when switching up to renditions larger than needed while preloads run. |
| `ReelPlayerConfig.startupQualityLimit` | Prepares HLS/DASH at a low rendition and switches up once playing, so parallel preparations stay small (Android, iOS). |
| `ReelFeedConfig.activeHeadStart` (300 ms) | How long preloads wait for an active item that is still preparing. |
| Initialize the manager early | The first native player is the most expensive one (hundreds of ms). |
| `idleTimeout` | Reusing an idle native player is cheaper than creating one; keep the default 30 s unless memory is tight. |
| Disk cache | Replays and scrolling back start from disk instead of the network (Android, iOS progressive). |

## Memory and decoders

| Lever | Effect |
| --- | --- |
| `ReelPoolConfig.maxPlayers` | Upper bound on native players, decoders and render targets. Leave it null for a device-adaptive limit (capped by `maxAdaptivePlayers`, 4). |
| `preloadAhead` / `preloadBehind` | Each prepared item holds a decoder and its buffer. 2 ahead + 1 behind fits a pool of 4. |
| `preloadBufferDuration` (5 s) | How much a prepared-but-paused item downloads and keeps buffered. Lower it for long videos on metered networks. |
| `controllerRetention` (20) | Controllers of far items are disposed; raise it only if you keep state on controllers. |
| `release()` | Give a player back as soon as a video is off screen in custom layouts (feeds do this for you). |
| `trimIdlePlayers()` | Destroy idle players immediately, for example when leaving the video section of the app. |

Memory warnings already shrink feeds' windows, release `background`
controllers and destroy idle players.

## Network

- On metered networks feeds preload 1 item ahead, with data saver none;
  adjust with `ReelNetworkPreloadPolicy`.
- Cap adaptive streams with `setVideoQualityLimit` on cellular.
- Give signed URLs a `cacheKey` so the cache recognizes them.

## UI

- Position is never pushed: use `controller.positions()` only where a
  progress bar is visible; it polls only while playing and listened to.
- `ReelPlaybackState` changes on state transitions only, so a
  `ValueListenableBuilder` on a controller rebuilds rarely.
- Give feed items stable ids so inserting or removing items does not
  re-prepare the video in view.
- Prefer `BoxFit.cover` with a poster image of the first frame; the poster
  disappears when the real first frame is rendered.

## Grids of previews

For several muted videos at once, set `exclusivePlayback: false`, keep
`maxPlayers` at the number of tiles that play simultaneously, and set the
priority of off-screen tiles to `background` so they give their players up
first.
