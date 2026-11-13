# Player manager

`ReelKitManager` owns the engine connection, a pool of native players and
every controller and feed created from it.

```dart
final manager = ReelKitManager(
  config: const ReelKitConfig(
    pool: ReelPoolConfig(maxPlayers: 3),        // omit for a device-adaptive limit
    player: ReelPlayerConfig(looping: true),    // defaults for controllers
    exclusivePlayback: true,                    // one video plays at a time
    lifecycle: ReelLifecycleConfig(),           // pause in background, resume after
    cache: ReelCacheConfig(maxBytes: 512 << 20),
    audio: ReelAudioConfig(),
    fullscreen: ReelFullscreenConfig(appOrientations: [DeviceOrientation.portraitUp]),
  ),
);
await manager.initialize();
// ...
await manager.dispose(); // disposes controllers, feeds and native players
```

Use one manager per independent playback context. The engine-wide parts
(disk cache size, audio settings) are taken from the first manager that
initializes the engine.

## The pool

A native player owns a decoder, buffers and a render target, so ReelKit
keeps at most `maxPlayers` of them and moves them between controllers.

- **Adaptive limit.** Without `maxPlayers`, the limit is the engine's
  `capabilities.recommendedMaxPlayers` (derived from memory and, on
  Android, the hardware decoder limit), capped at `maxAdaptivePlayers` (4).
- **Priorities.** When the pool is full, a controller with a higher
  `priority` (`background < preload < visible < active`) takes the player
  of the lowest-priority controller. That controller returns to `idle` and
  prepares again on its next `initialize` or `play`. A request that finds
  no player of lower priority fails with `poolExhausted`.
- **Reuse.** Released players stay idle for `idleTimeout` (30 s) and are
  reused instead of creating new native players; `trimIdlePlayers()`
  destroys them at once.
- **Decoder shortage.** When preparation fails with `decoderUnavailable`
  while other players of the pool hold videos, the limit drops to the
  number of those players and the video is retried once
  (`adaptToDecoderFailures`).

```dart
final stats = manager.poolStats;
print('${stats.leased}/${stats.maxPlayers} leased, ${stats.idle} idle, '
    '${stats.created} created, ${stats.reused} reused, '
    '${stats.revoked} revoked, by priority ${stats.leasedByPriority}');
```

## Exclusive playback

By default `play` on one controller pauses the manager's other controllers,
and when several `play` calls overlap the most recent one wins.
`manager.activeController` is a `ValueListenable` of the controller that is
playing. Set `exclusivePlayback: false` for grids of muted previews that
play together.

## App lifecycle and memory

- When the app is hidden, playing controllers pause and resume when it is
  shown again (`ReelLifecycleConfig`). Transient `inactive` states, such as
  the notification shade, do not pause.
- On a memory warning, feeds shrink their preload window, controllers with
  `background` priority give their players back and idle players are
  destroyed.
- `manager.pauseAll()` pauses everything, for example when another route
  covers your own player screen. `ReelFeedView` does this for its feed by
  itself (see [Feeds](feed.md#pausing)).

## Network status

`manager.networkStatus` is a `ValueListenable<ReelNetworkStatus>`
(connected, metered, constrained, transport). Feeds use it to size the
preload window; controllers that failed for lack of network retry when it
returns.

```dart
ValueListenableBuilder<ReelNetworkStatus>(
  valueListenable: manager.networkStatus,
  builder: (context, status, _) =>
      status.isConnected ? const SizedBox.shrink() : const Text('Offline'),
);
```
