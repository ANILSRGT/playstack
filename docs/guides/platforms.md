# Platform support

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Engine | Media3 1.11.1 ExoPlayer | AVPlayer | HTMLVideoElement |
| Minimum | API 24 | iOS 15 | Current Chromium, Firefox, Safari |
| Rendering | `SurfaceProducer` texture | `FlutterTexture` (`AVPlayerItemVideoOutput`) | Platform view |
| Play, pause, seek, loop, volume, mute, speed | Yes | Yes | Yes |
| First frame while paused (preparing ahead) | Yes | Yes | Yes |
| Rotation metadata | Yes | Yes | Applied by the browser |
| `ReelSource.network` | Yes | Yes | Yes |
| Custom HTTP headers | Yes | Yes (`AVURLAssetHTTPHeaderFieldsKey`) | No: `<video>` cannot send them; rejected with `invalidSource` |
| `ReelSource.asset` | Yes | Yes | Yes |
| `ReelSource.file` | Yes | Yes | No (`invalidSource`) |
| `ReelSource.memory` | Yes (in memory) | Yes (staged to a temporary file) | Yes (Blob URL) |
| HLS | Yes | Yes | Safari natively; elsewhere with HLS.js loaded by the app (`window.Hls`), otherwise `unsupportedFormat` |
| DASH | Yes | No (`unsupportedFormat`) | No (`unsupportedFormat`) |
| Autoplay with sound | Yes | Yes | Blocked until a user gesture (`playbackNotAllowed`); muted autoplay works |
| Disk cache | Progressive files and HLS/DASH segments | Progressive files; not HLS | No: browser HTTP cache only |
| Audio track selection | Yes | Yes (media selection) | Only where the browser exposes `audioTracks` (Safari) |
| Subtitle tracks, text delivered to Dart | Yes (in-band and HLS/DASH) | Yes (legible media selection) | Tracks the browser exposes; in-band MP4 text is not exposed by Chromium |
| Video rendition selection | Yes | No: AVFoundation chooses; listed for information | No |
| Video quality limit (bitrate, size) | Yes | Yes (`preferredPeakBitRate`, `preferredMaximumResolution`) | No (`notImplemented`) |
| Metadata: frame rate, bitrate, codec, live | Yes | Yes | Live flag only |
| Preload buffer limit | Yes (load control, hard limit) | Yes (`preferredForwardBufferDuration`, a preference) | No: browsers decide |
| Network status | `ConnectivityManager` (adds `ACCESS_NETWORK_STATE`) | `NWPathMonitor`, including Low Data Mode | `navigator.onLine`; metering and data saver only where `navigator.connection` exists (Chromium) |
| Audio focus / session | Audio focus for audible players, pause when headphones are unplugged | Optional `AVAudioSession` category; interruptions and route loss reported; resume after interruption | Managed by the browser |
| Fullscreen | `SystemChrome` immersive mode, optional orientation lock, rotate back and restore policy | Same; iPad multitasking ignores orientation locks | Fullscreen API (user gesture); orientation lock where supported |
| Decoder-shortage detection | `ERROR_CODE_DECODER_INIT_FAILED` | `AVError.decoderTemporarilyUnavailable` | Not distinguishable |
| Same controller in two views | Yes | Yes | No: one `<video>` element, one view at a time |

`ReelPlatformCapabilities` (`manager.capabilities`) reports these at run
time and never claims a feature the engine does not provide:

```dart
final caps = manager.capabilities;
if (!caps.supportsDash) useHlsInstead();
if (caps.supportsDiskCache) showCacheSettings();
print('${caps.engineName} ${caps.engineVersion}, '
    'up to ${caps.recommendedMaxPlayers} players recommended');
```

## What was verified where

- **Android and iOS:** the integration suite in
  `packages/reelkit/example/integration_test` passes on an Android 16
  (API 36) arm64 emulator and an iOS 26.5 simulator, including the
  benchmark. Rendering orientation was checked against ffmpeg reference
  frames.
- **Not verified on device:** the decoder-shortage retry and audio
  interruptions (unit tests only: emulators do not run out of decoders or
  receive calls on demand); physical-device performance.
- **Web:** compiled to JS and Wasm and unit tested; the integration suite,
  HLS.js and the Fullscreen API have not been run in a browser yet.
