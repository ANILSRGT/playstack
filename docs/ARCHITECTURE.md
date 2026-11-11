# ReelKit architecture

ReelKit manages native video playback. The application owns the look: the
optional feed view handles paging and transitions, and every control on it
can be replaced. This
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
 Application UI (ReelFeedView + controls, or PageView, ListView...)
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

**Playback intent, not frame progress.** Engines report `isPlaying` as
"playback is requested" (Android `playWhenReady`, iOS `rate != 0`, web
`play`/`pause` events). Stalls are reported separately as `buffering`, so a
buffering video stays `playing` with `isBuffering == true` instead of
flickering to `paused`. Android clears `playWhenReady` at the end of a
non-looping video so the next `play()` is a new request.

**Rotation contract.** Engines report the size of the frames as they arrive
in the render target plus the rotation Flutter must still apply.
- Android: Media3 reports `VideoSize` upright because the decoder rotates
  through the surface transform. Flutter's `SurfaceTexture` backend honours
  that transform (`handlesCropAndRotation() == true`); the `ImageReader`
  backend does not, so the engine un-swaps the size and reports
  `Format.rotationDegrees`.
- iOS: `AVPlayerItemVideoOutput` delivers unrotated frames; the rotation comes
  from the track's `preferredTransform`.
- Web: browsers rotate `<video>` themselves; rotation is always 0.
Verified by screenshot on an Android 16 emulator and an iOS simulator
against ffmpeg's auto-rotated reference frame.

**iOS frame pump.** A `CADisplayLink` copies new pixel buffers only while
playback is requested or a frame is expected (new source or seek). A paused,
prepared player costs no per-frame work, yet still shows its first frame,
which feeds need for videos prepared ahead.

**Idle players hold nothing.** When a controller is released or disposed, the
pool calls `clearSource` (Android `stop()` + `clearMediaItems()`, iOS
`replaceCurrentItem(nil)`, web `removeAttribute('src')` + `load()`) before
keeping the player for reuse. A player that cannot be cleared is destroyed.

**Tracks are pulled, subtitles are pushed.** Engines emit a
`tracksChanged` event and the controller reads the list once
(`getTracks`); subtitle text changes are pushed as `cues` events because they
are needed at cue time. Both are low frequency. Subtitles are plain text so
that the application renders them with its own widgets; source styling and
positioning are not preserved. Track preferences live in the controller and
are re-applied after every preparation, because a pooled controller can lose
and regain its native player. iOS hides AVFoundation's synthesized
"forced-only" subtitle variants, which are not a viewer choice.

**Position stream.** `positions()` polls only while it has a listener and
the video is playing, plus once after every state change or seek. A paused
player causes no channel traffic.

**App lifecycle.** The manager listens to `AppLifecycleState`. On `hidden`
(and `paused`/`detached`) it pauses its playing controllers and remembers
them; on `resumed` it resumes only those. `inactive` is ignored because it is
transient (notification shade, incoming call banner).

**Exclusive playback.** A `ReelPlaybackCoordinator` per manager decides who
may play. `play` registers the request synchronously, before the command is
queued, and asks every other controller that plays or has a pending `play`
to yield. Yielding is itself a queued command that pauses only if that
controller has not requested playback again since, and a queued `play` that
has been superseded completes without starting playback. Ordering therefore
follows call order, not preparation speed: a slow preparation cannot start
over a later request. With `exclusivePlayback: false` the coordinator only
tracks the active (most recently started) controller.

**Decoder shortage.** Hardware decoder instances are shared device-wide, so
`recommendedMaxPlayers` is only an estimate. Engines report a decoder that
exists but cannot be allocated as `decoderUnavailable` (Android
`ERROR_CODE_DECODER_INIT_FAILED`, iOS `decoderTemporarilyUnavailable`). The
pool attributes the failure to itself only when other controllers hold
leased players; it then lowers its limit to that number, the failing
controller gives its player back (destroyed, being over the limit) and
retries once by taking a player from a lower-priority controller. Each lease
records the pool's limit epoch, so concurrent failures caused by the same
shortage lower the limit once. The lowered limit lasts for the manager's
lifetime. If no player can be taken, the original `decoderUnavailable` error
is reported. Decoder failures during playback (after preparation) are
reported, not retried.

**Feed view.** `ReelFeedView` is a thin layer over `ReelFeedManager`.
It is a `PageView` that reports page changes with `setActiveIndex` and
follows the feed when the active index moves on its own (items inserted
above). Pages are keyed by item id, so their state survives insertions.
Transitions are transforms computed from each page's offset relative to
the scroll position. There are no custom render objects, so dragging and
programmatic moves (`animateToPage`) animate the same way. Slide is the
identity and skips the per-frame work. Everything above the video comes
from `controlsBuilder`. The defaults (`ReelDefaultControls`) are built
from small public widgets that apps can reuse.

The main constructor takes the app's own items (`List<T>`). The view
creates the manager (with the `reels` presets) and the feed, generates
item ids, and disposes both when it is removed. A junior developer never
handles ids, managers or batching. A new `items` list that extends the
previous one is appended; any other list replaces the feed. `onLoadMore`
runs one call at a time, and an empty result ends the feed.
`ReelFeedView.feed` keeps the lower-level path for apps that manage a
`ReelFeedManager` themselves; that feed is never disposed by the view.

**Memory pressure.** Idle native players are destroyed and `background`
controllers lose their players (they prepare again on demand). Releases are
awaited before trimming so that their players are destroyed too.

**Feed manager.** `ReelFeedManager` is the only component that knows about
item order. It never owns a widget: the app reports the item in view and
the feed translates that into controller priorities and commands. Every
change (index, items, network, memory, pool size) re-plans synchronously:
priorities are set and items outside the window are released first (so the
active item rarely needs revocation), then the active item is played, then
preloads run in order (+1, -1, +2, ...) after the active item has
prepared, so it gets the bandwidth and the first decoder. A plan number
stops preload loops of windows that were left; `release()` fails an
in-flight preparation immediately, which detaches its source on the native
side. Controllers far outside the window are disposed to keep endless feeds
flat; the native player count is bounded by the pool regardless.

**Preload window.** `ReelPreloadWindow.resolve` is a pure function of the
configuration, network status, low-RAM flag, memory-warning cooldown and
the pool size (`maxPlayers - 1`, so it follows decoder-shortage
reductions). It is unit-tested on its own.

**Bounded preload buffering.** Media3's `DefaultLoadControl` would buffer
up to 50 s of a paused, prepared player. `PreloadLoadControl` wraps it and
stops loading at the configured duration while `playWhenReady` is false,
so starting playback lifts the cap without a channel call. iOS sets
`preferredForwardBufferDuration` while paused and automatic buffering when
playing; AVFoundation treats it as a hint. Browsers expose no control.

**Network status.** Android uses a default-network callback registered only
while Dart listens; iOS keeps one `NWPathMonitor` (cheap, push based) so the
status can be read synchronously; web reads `navigator.onLine` and
`navigator.connection`. Unsupported values are reported as unknown, never
guessed.

**Disk cache.** Android uses one process-wide Media3 `SimpleCache` (it locks
its directory) with an LRU evictor. A `ManifestBypassDataSource` sends
`.m3u8`/`.mpd` requests to the network and everything else through
`CacheDataSource`: live manifests change under the same URL, while segment
URLs are immutable. iOS has no cache for progressive downloads, so the
engine rewrites the URL scheme, answers `AVAssetResourceLoader` requests
from a sparse file plus a list of valid byte ranges, and downloads (and
stores) only the missing part of each request. Entries in use are never
evicted; the index is written when an entry is released. HLS stays with
AVFoundation on iOS. The first manager's configuration sizes the cache for
the whole process.

**Fullscreen and orientation.** Flutter cannot read the preferred
orientations an app set, so restoring "what was there" is impossible
without help. ReelKit therefore restores an explicit, registered policy
(`ReelFullscreenConfig`, updatable with `setAppPolicy`), and leaves the
orientation untouched unless fullscreen asks for one. When it did lock the
orientation, exit first locks to the orientation the view had before
(portrait or landscape, from the view size) for a moment and then applies
the policy: unlocking alone leaves the interface sideways on iOS until the
device moves. Enter/exit calls are serialized. On web the same API maps to
the Fullscreen API and `screen.orientation.lock`, whose failures outside
supporting browsers are ignored rather than faked.

**Audio.** Android players take audio focus only while audible, so muted
autoplay never stops the user's music, and `setHandleAudioBecomingNoisy`
pauses on unplugged headphones. Focus losses and transient suppression are
reported as interruption events. iOS leaves `AVAudioSession` to the host
unless a category is configured, applied lazily before the first `play`;
interruption and route-change notifications are attributed to players that
were asked to play.

**Retry.** Retries live in the controller, not the engines: a preparation
loop with exponential backoff for `network` and `timeout`, cancellable by
`release`/`dispose`; recovery from a playback error re-prepares on the same
lease, seeks to the failed position and resumes. The manager retries
controllers that failed offline when the network returns.

**Zones and idle futures.** `AsyncLock` keeps no future while idle: a
completed future schedules listeners in the zone that created it, which
deadlocked controllers created in one test zone and disposed from another.
Manager disposal does not await subscription cancellation for the same
reason.

**Source replacement.** `setSource` keeps the controller's native player and
renews the lease generation, so late events of the old source are dropped
without a release/acquire round trip.

## Platform risks

| Risk | Platform | Mitigation |
| --- | --- | --- |
| Hardware decoder instances are limited and shared with other apps; `maxSupportedInstances` is an upper bound, not a guarantee. | Android | Conservative pool limit; `decoderUnavailable` lowers the limit and retries once on a lower-priority player. Unit-tested; not yet reproduced on a physical low-end device. `ERROR_CODE_DECODER_INIT_FAILED` can also mean an unsupported configuration; the retry is then wasted once. |
| `SurfaceProducer` surfaces can be destroyed on background and recreated. | Android | Callback re-binds `setVideoSurface`; never cache `surface`. |
| Rotation handling differs between Flutter's Android texture backends. | Android | Engine reports the remaining rotation per backend; verified on an API 36 emulator (ImageReader). The SurfaceTexture path (older devices) is not yet device-verified. |
| No public API for concurrent decode sessions; many `AVPlayer`s with items increase memory and can fail silently. | iOS | Memory-based limit; items are detached from released players; `decoderTemporarilyUnavailable` triggers the decoder-shortage handling. |
| `AVPlayerItemVideoOutput` + display link costs CPU if left running. | iOS | Display link only while playing or awaiting a frame; paused players keep the last buffer. |
| HTTP headers use `AVURLAssetHTTPHeaderFieldsKey`, which is not in the public headers. | iOS | Widely used (also by `video_player`); revisit with `AVAssetResourceLoader` if Apple removes it. |
| Audio session category belongs to the host app. | iOS | ReelKit does not change it unless `ReelAudioConfig.iosAudioSessionCategory` is set, and then only when playback starts. |
| Autoplay with sound is blocked; only muted autoplay is allowed. | Web | Muted autoplay policy and typed errors (milestone 2/6). |
| `<video>` cannot send custom HTTP headers; no disk cache guarantees; HLS only native on Safari. | Web | Rejected with typed errors and reported through capabilities. HLS.js is used when the app loads it; not yet run in a browser. |
| Platform views are costlier than textures. | Web | Unavoidable; keep the pool small. |
| A platform view's element can be in one place only. | Web | One `ReelVideoView` per controller at a time; documented in the rendering and fullscreen guides. |
| Orientation and fullscreen APIs differ per platform and per window mode (iPad multitasking, Android large screens, browser fullscreen permission). | All | Explicit orientation coordination, restore registered policy (milestone 6). |

## Measuring

Start latency is measured until the playback position moves, not until the
engine accepts `play`: both engines accept a prepared video's `play` in a
few milliseconds but start their clock only once audio output runs (about
100 ms in the baseline). `ReelPlayerMetrics.lastStartLatency` and
`ReelFeedStats` report the cheaper "accepted" signal because they must not
poll; the example benchmark polls the position instead. Method and
baseline: [BENCHMARKS.md](BENCHMARKS.md).

## Milestone status

See the root `README.md` for what works today.
