# ReelKit architecture

ReelKit manages native video playback; the application owns the UI. This
document records the structure and the decisions behind it. It is updated with
each milestone.

## Packages

ReelKit is a federated Flutter plugin developed in a Dart pub workspace.

| Package | Role |
| --- | --- |
| `packages/reelkit` | App-facing API: `ReelKitManager`, `ReelPlayerController`, `ReelVideoView`, configuration, player pool. Pure Dart. |
| `packages/reelkit_platform_interface` | Engine contract (`ReelKitPlatform`) and shared models: sources, video info, events, typed errors. |
| `packages/reelkit_android` | Android engine: Kotlin, AndroidX Media3 ExoPlayer, Flutter `SurfaceProducer` textures. |
| `packages/reelkit_ios` | iOS engine: Swift, AVFoundation `AVPlayer`, `FlutterTexture` + `AVPlayerItemVideoOutput`. Swift Package Manager and CocoaPods. |
| `packages/reelkit_web` | Web engine: Dart, `HTMLVideoElement` through a platform view. |
| `packages/reelkit/example` | Example and diagnostics app, device integration tests. |
| `pigeons/reelkit_messages.dart` | Single typed wire schema for Android and iOS. Run `tool/generate_pigeons.sh` after changing it. |

## Layers

```
 Application UI (PageView, ListView, custom overlays...)
        │ commands                    ▲ ValueListenable<ReelPlaybackState>
 ┌──────▼─────────────────────────────┴──────────┐
 │ ReelPlayerController (one per video, cheap)   │  serialized commands,
 │                                               │  state machine
 ├───────────────────────────────────────────────┤
 │ ReelKitManager  ── ReelPlayerPool             │  lease / reuse / revoke,
 │   event routing     (bounded native players)  │  hard player limit
 ├───────────────────────────────────────────────┤
 │ ReelKitPlatform (platform interface)          │
 ├──────────────┬───────────────┬────────────────┤
 │ Pigeon       │ Pigeon        │ JS interop     │
 │ Media3       │ AVPlayer      │ <video>        │
 └──────────────┴───────────────┴────────────────┘
        frames go straight to Flutter textures / platform views
```

## Key decisions

**Controllers do not own native players.** A controller is a Dart handle for
one source. It leases a native player from the pool only when it is
initialized or played. Feeds can therefore create a controller per item
without allocating decoders per item.

**Bounded pool with priority-based revocation.** The pool never holds more
than `maxPlayers` native players; all pool mutations go through one async
lock, so concurrent requests cannot race past the limit. When full, a request
takes the player of the lowest-priority, least recently used controller whose
priority is strictly lower (`background < preload < visible < active`).
Equal priority never steals; the request fails with `poolExhausted` instead.

**Adaptive limit.** `ReelPoolConfig.maxPlayers` defaults to null, which uses
the engine's `recommendedMaxPlayers` capped at `maxAdaptivePlayers` (4). The
recommendation comes from real device data: Android uses the low-RAM flag,
total memory and the hardware H.264 decoder `maxSupportedInstances`; iOS uses
physical memory (there is no public decoder-instance API); web uses
`navigator.deviceMemory` where available. These are heuristics and are
documented as such; an explicit `maxPlayers` always wins.

**Generations against stale events.** Every lease (and every retry) gets a
new generation number that is sent with `setSource`; native engines tag each
event with it. A controller ignores events whose generation does not match its
current lease, so a reused player cannot leak late events of a previous video
into the next one.

**No high-frequency traffic.** Frames never cross a channel. Events are
state transitions only. Position is pulled on demand (`getPosition`) instead
of being pushed every tick, and `ReelPlaybackState` deliberately excludes
position so that `ValueListenableBuilder`s do not rebuild every frame. When a
pooled player changes owner, only settings that differ from what the native
player already has are sent.

**Serialized commands per controller.** `play`, `pause`, `seekTo`, settings
and `dispose` run one at a time in call order. Commands still queued when
`dispose` is called complete without effect; commands after `dispose` throw
`ReelKitErrorCode.disposed`.

**Rendering.**
- Android: `TextureRegistry.createSurfaceProducer()`. The producer's callback
  re-binds ExoPlayer when Flutter recreates the surface (backgrounding on
  Impeller), instead of caching a surface that may be destroyed.
- iOS: `FlutterTexture` fed by `AVPlayerItemVideoOutput` pixel buffers, not an
  `AVPlayerLayer` platform view. IOSurface-backed buffers are imported by the
  engine without a copy, and textures compose with arbitrary Flutter widgets
  without the overlay and thread-merging costs platform views add inside
  scrolling feeds. The cost is a display-link-driven buffer pull while
  playing, which milestone 2 limits to playing players only.
- Web: `HTMLVideoElement` in a platform view; browsers offer no texture path.
- `ReelVideoView` lays the render widget out at the video's display size
  (pixel aspect ratio and outstanding rotation applied) and scales it with
  `FittedBox`, so every `BoxFit` and `Alignment` behaves exactly as for images
  on all platforms. Engines report the rotation still to be applied (0 when
  they already rotate frames).

## Platform risks

| Risk | Platform | Mitigation |
| --- | --- | --- |
| Hardware decoder instances are limited and shared with other apps; `maxSupportedInstances` is an upper bound, not a guarantee. | Android | Conservative pool limit; decoder errors are typed (`decoder`) so the pool can shrink (milestone 4). |
| `SurfaceProducer` surfaces can be destroyed on background and recreated. | Android | Callback re-binds `setVideoSurface`; never cache `surface`. |
| Rotation handling differs between Flutter's Android texture backends. | Android | Engine reports the remaining rotation per video; verified on device in milestone 2. |
| No public API for concurrent decode sessions; many `AVPlayer`s with items increase memory and can fail silently. | iOS | Memory-based limit; items are detached from released players (milestone 2). |
| `AVPlayerItemVideoOutput` + display link costs CPU if left running. | iOS | Display link only while playing; paused players keep the last buffer. |
| Audio session category belongs to the host app. | iOS | ReelKit will not change it unless configured (milestone 6). |
| Autoplay with sound is blocked; only muted autoplay is allowed. | Web | Muted autoplay policy and typed errors (milestone 2/6). |
| `<video>` cannot send custom HTTP headers; no disk cache guarantees; HLS only native on Safari. | Web | Reported through capabilities; HLS.js evaluated in milestone 2. |
| Platform views are costlier than textures. | Web | Unavoidable; keep the pool small. |
| Orientation and fullscreen APIs differ per platform and per window mode (iPad multitasking, Android large screens, browser fullscreen permission). | All | Explicit orientation coordination, restore registered policy (milestone 6). |

## Milestone status

See the root `README.md` for what works today.
