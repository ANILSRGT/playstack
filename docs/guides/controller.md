# Player controller

`ReelPlayerController` controls one video. Create it with
`manager.createController`; it is a `ValueListenable<ReelPlaybackState>`.

```dart
final controller = manager.createController(
  const ReelSource.network('https://example.com/a.mp4'),
  config: const ReelPlayerConfig(looping: true, muted: true),
);
```

## Sources

```dart
ReelSource.network(
  'https://cdn.example.com/v/42.m3u8',
  headers: {'Authorization': 'Bearer $token'}, // not on web
  cacheKey: 'video-42',                        // stable key for signed URLs
  cachePolicy: ReelCachePolicy.cache,          // or bypass for private media
  id: 'post-42',
);
ReelSource.asset('assets/intro.mp4');
ReelSource.file('/path/on/device.mp4');        // not on web
ReelSource.memory(bytes, mimeType: 'video/mp4'); // short clips only
```

The format (progressive, HLS, DASH) is detected from the URL; pass
`formatHint` when the URL has no extension.

## Lifecycle

| Call | Effect |
| --- | --- |
| `initialize()` | Leases a native player and prepares the source; renders the first frame while paused. Completes when ready. |
| `play()` | Prepares if needed, then plays. With exclusive playback, pauses the manager's other controllers. |
| `pause()` / `stop()` | Pause; `stop` also seeks to the start. |
| `setSource(source)` | Replaces the video on the same native player. |
| `release()` | Gives the native player back to the pool, keeps the controller. The next `initialize`/`play` prepares again. |
| `reinitialize()` | Releases and prepares from the beginning. |
| `retry()` | After an error: prepares again, seeks back and resumes if it was playing. |
| `dispose()` | Releases the player and disposes the controller. |

Every command is serialized per controller, so calls may be issued without
awaiting the previous one.

## State

```dart
ValueListenableBuilder<ReelPlaybackState>(
  valueListenable: controller,
  builder: (context, state, _) {
    if (state.hasError) return Text(state.error!.message);
    if (!state.isInitialized) return const CircularProgressIndicator();
    return Text('${state.status.name}, buffering: ${state.isBuffering}');
  },
);
```

`ReelPlaybackStatus` is one of `idle`, `initializing`, `ready`, `playing`,
`paused`, `completed`, `error`, `disposed`. The state also carries
`videoInfo` (size, rotation, duration, frame rate, bitrate, codec, live),
`isBuffering`, `hasRenderedFirstFrame`, `isAttached` (holds a native
player), `volume`, `isMuted`, `isLooping` and `playbackSpeed`.

## Position

Position is not part of the state, so listeners do not rebuild every frame.

```dart
final now = await controller.getPosition(); // position and buffered
final left = await controller.getRemaining();

// Polls only while playing and listened to.
StreamBuilder<ReelPositionSnapshot>(
  stream: controller.positions(interval: const Duration(milliseconds: 200)),
  builder: (context, snapshot) => LinearProgressIndicator(
    value: _fraction(snapshot.data, controller.value.duration),
  ),
);
```

## Seeking and settings

```dart
await controller.seekTo(const Duration(seconds: 30));
await controller.seekBy(const Duration(seconds: -5));
await controller.fastForward(); // 10 s by default
await controller.rewind();
await controller.setLooping(true);
await controller.setVolume(0.5);
await controller.setMuted(true);
await controller.setPlaybackSpeed(1.5);
```

## Priority

`controller.priority` (`background < preload < visible < active`) decides
which controller keeps a native player when the pool is full. Playing
controllers are `active` automatically. See [Player manager](manager.md).

## Interruptions and metrics

```dart
controller.interruptions.listen((interruption) {
  // audioInterruption (call, other app) or audioRouteLost (headphones)
  showSnackBar('Paused: ${interruption.type.name}');
});

final metrics = controller.metrics;
print('${metrics.lastPreparationTime} ${metrics.lastTimeToFirstFrame} '
    '${metrics.lastStartLatency}');
```

Tracks, subtitles and quality limits: [Tracks and subtitles](subtitles.md).
Errors and retries: [Errors and retry](errors.md).
