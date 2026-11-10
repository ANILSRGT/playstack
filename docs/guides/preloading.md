# Preloading

A feed prepares items around the active one so that they start instantly.
Preparing means leasing a native player, loading the beginning of the
video and rendering its first frame while paused.

## Order and concurrency

1. The active item is prepared and played first.
2. Only when it is ready do preloads start: the next item, then the
   previous one, then the one after next, and so on.
3. At most `maxConcurrentPreloads` (1) preparations run at once, so
   preloads never compete with the active item for bandwidth.
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
