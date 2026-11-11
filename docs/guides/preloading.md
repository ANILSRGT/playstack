# Preloading

A feed prepares items around the active one so that they start instantly.
Preparing means leasing a native player, loading the beginning of the
video and rendering its first frame while paused.

## Order and concurrency

1. The active item is prepared and played first.
2. Preloads start when it is ready, or after `activeHeadStart` (300 ms)
   if it is still preparing: the next item, then the previous one, then
   the one after next, and so on. HLS and DASH startup is mostly round
   trips, so waiting longer for a slow active item would leave a fast
   swiper arriving at items nobody started preparing.
3. At most `maxConcurrentPreloads` (1) preparations run at once besides
   the active item.
4. When the active index moves, preloads outside the new window are
   cancelled immediately and their players returned. Scrolling fast through
   a hundred items does not queue a hundred preparations.

## The window

`preloadAhead` (2) and `preloadBehind` (1) are upper bounds. The window
actually applied (`feed.preloadWindow`) is reduced by:

| Condition | Window |
| --- | --- |
| Metered network (cellular, hotspot) | `network.meteredPreloadAhead` (1) ahead, `meteredPreloadBehind` (0) behind |
| Data saver, Low Data Mode, `saveData` | `network.constrainedPreloadAhead` (0) ahead, none behind |
| Offline | Network sources are not preloaded; local ones are |
| Low-RAM device | `lowMemoryPreloadAhead` (1) ahead, none behind |
| Memory warning | 1 ahead, none behind, for `memoryPressureCooldown` (30 s) |
| Pool size | At most `maxPlayers - 1` items, items behind give way first |

```dart
const ReelFeedConfig(
  preloadAhead: 3,
  preloadBehind: 1,
  maxConcurrentPreloads: 1,
  network: ReelNetworkPreloadPolicy(meteredPreloadAhead: 1),
  lowMemoryPreloadAhead: 1,
  retryFailedPreloads: true,
);
```

## Fast swiping

At two or three swipes a second the default window (2 ahead, one at a
time) is outrun: the user reaches items that are still preparing. What
works, measured with the demo app's HLS feed on an iOS simulator at 350 ms
per swipe (prepared on arrival: 10-35 % with the defaults, 70-85 % with
these settings):

```dart
final manager = ReelKitManager(
  config: const ReelKitConfig(
    pool: ReelPoolConfig(maxPlayers: 7),
    player: ReelPlayerConfig(
      // Prepare at a low rendition; playing switches up.
      startupQualityLimit: ReelVideoQualityLimit(maxBitrate: 1600000),
    ),
  ),
);
final feed = manager.createFeed(
  items,
  config: const ReelFeedConfig(
    preloadAhead: 5,
    preloadBehind: 1,
    maxConcurrentPreloads: 3,
  ),
);
```

`startupQualityLimit` matters most: engines start with the first
rendition of the master playlist, often 1080p, and five parallel 1080p
starts saturate the connection. The cost is that the first seconds of a
video play at the startup rendition. Also show a poster
(`ReelVideoView.poster`, a thumbnail from your video service) so an item
that is not ready yet never shows black. Measure on your devices and
network with the demo's `integration_test/swipe_test.dart`.

Cap quality to the view as well (`ReelPlayerConfig.videoQualityLimit`, in
physical pixels): a landscape video in a portrait feed is only as wide as
the screen, and switching up to its 1080p rendition while the next items
preload can outrun the network, so playback stops until the segment
arrives. Some streams declare less bandwidth than their 1080p rendition
needs, which makes this worse. Lift the limit in fullscreen. The demo's
`integration_test/stall_test.dart` reports any time playback stops.

## Buffer limit

A prepared item that is not playing buffers only
`ReelPlayerConfig.preloadBufferDuration` (5 s), so preloading three items
does not download three whole videos. Once it plays, the engine's normal
buffering applies. Android enforces the limit; iOS treats it as a
preference (`preferredForwardBufferDuration`); browsers decide themselves.

## Preloading without a feed

Controllers can be prepared by hand:

```dart
final next = manager.createController(nextSource)
  ..priority = ReelPlayerPriority.preload;
await next.initialize();     // first frame ready, paused, 5 s buffered
// later
await next.play();           // starts almost instantly
```

Lower-priority controllers lose their player first when the pool is full.

## With the disk cache

With caching enabled (the default on Android and iOS), preloaded bytes are
written to the cache, so a preloaded item that is released and later
played again does not download its beginning twice. See
[Caching](caching.md).
