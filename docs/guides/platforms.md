# Platform support

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Engine | Media3 1.11.1 ExoPlayer | AVPlayer | HTMLVideoElement |
| Minimum | API 24 | iOS 15 | Current Chromium, Firefox, Safari |
| Rendering | `SurfaceProducer` texture | `FlutterTexture` (`AVPlayerItemVideoOutput`) | Platform view |
| Play, pause, seek, loop, volume, mute, speed | Yes | Yes | Yes |
| First frame while paused (preparing ahead) | Yes | Yes | Yes |
| Rotation metadata | Yes | Yes | Applied by the browser |
| `PlayStackSource.network` | Yes | Yes | Yes |
| Custom HTTP headers | Yes | Yes (`AVURLAssetHTTPHeaderFieldsKey`) | No: `<video>` cannot send them; rejected with `invalidSource` |
| `PlayStackSource.asset` | Yes | Yes | Yes |
| `PlayStackSource.file` | Yes | Yes | No (`invalidSource`) |
| `PlayStackSource.memory` | Yes (in memory) | Yes (staged to a temporary file) | Yes (Blob URL) |
| HLS | Yes | Yes | Safari natively; elsewhere with HLS.js loaded by the app (`window.Hls`), otherwise `unsupportedFormat` |
| DASH | Yes | No (`unsupportedFormat`) | No (`unsupportedFormat`) |
| Autoplay with sound | Yes | Yes | Blocked until a user gesture (`playbackNotAllowed`); muted autoplay works |
| Disk cache | Progressive files and HLS/DASH segments | Progressive files; not HLS | No: browser HTTP cache only |
| Audio track selection | Yes | Yes (media selection) | Only where the browser exposes `audioTracks` (Safari) |
| Subtitle tracks, text delivered to Dart | Yes (in-band and HLS/DASH) | Yes (legible media selection) | Tracks the browser exposes; in-band MP4 text is not exposed by Chromium |
| Video rendition selection | Yes | No: AVFoundation chooses; listed for information | No |
| Video quality limit (bitrate, size) | Yes (inside adaptive selection, no rebuffer) | Yes (`preferredPeakBitRate`, `preferredMaximumResolution`) | No (`notImplemented`) |
| Metadata: frame rate, bitrate, codec, live | Yes | Yes | Live flag only |
| Preload buffer limit | Yes (load control, hard limit) | Yes (`preferredForwardBufferDuration`, a preference) | No: browsers decide |
| Network status | `ConnectivityManager` (adds `ACCESS_NETWORK_STATE`) | `NWPathMonitor`, including Low Data Mode | `navigator.onLine`; metering and data saver only where `navigator.connection` exists (Chromium) |
| Audio focus / session | Audio focus for audible players, pause when headphones are unplugged | Optional `AVAudioSession` category; interruptions and route loss reported; resume after interruption | Managed by the browser |
| Fullscreen | `SystemChrome` immersive mode, optional orientation lock, rotate back and restore policy | Same; iPad multitasking ignores orientation locks | Fullscreen API (user gesture); orientation lock where supported |
| Media controls, background sound | Media3 `MediaSession` and `PlayStackMediaService` | `MPNowPlayingInfoCenter`, `audio` background mode | No |
| Offline downloads | Media3 `DownloadManager`: progressive, HLS, DASH; background with `PlayStackDownloadService` | Background `URLSession` (progressive), `AVAssetDownloadURLSession` (HLS, devices only) | No |
| Picture-in-Picture | Activity mode, API 26+ | `AVPictureInPictureController` | No |
| Device orientation sensors | `OrientationEventListener` | `UIDevice` orientation notifications | No |
| Decoder-shortage detection | `ERROR_CODE_DECODER_INIT_FAILED` | `AVError.decoderTemporarilyUnavailable` | Not distinguishable |
| Same controller in two views | Yes | Yes | No: one `<video>` element, one view at a time |
| DRM | Widevine, PlayReady, ClearKey (secure `SurfaceView`) | FairPlay (`AVPlayerLayer`) | No |
| Live streams: window, live edge | Yes | Yes | Yes |
| Audio only | Video track disabled | Video tracks disabled | Element hidden |
| Frames for the scrub preview | `MediaMetadataRetriever` (MP4, files) | `AVAssetImageGenerator` (MP4, files) | No |
| Screen brightness | Window brightness | `UIScreen.brightness` | No |
| AirPlay | No | `AVRoutePickerView` | No |
| Chromecast (`playstack_cast`) | Google Cast SDK | Google Cast SDK (CocoaPods) | No |
| Subtitle files, analytics, ads, cues, series, sleep timer | Yes (Dart) | Yes (Dart) | Yes (Dart) |

`PlayStackPlatformCapabilities` (`manager.capabilities`) reports these at run
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
  `packages/playstack/example/integration_test` passes on an Android 16
  (API 36) arm64 emulator and an iOS 26.5 simulator, including the
  benchmark. Rendering orientation was checked against ffmpeg reference
  frames.
- **Physical devices:** the integration suite (Picture-in-Picture included)
  and the benchmark pass on a Redmi Note 17 Pro Max 5G (Android 16) and an
  iPhone 11 (iOS 26.6.1).
- **Not verified:** DRM, AirPlay and Chromecast (they need licenses and
  receivers); the decoder-shortage retry and audio interruptions (unit
  tests only).
- **Web:** the integration suite passes in headless Chromium 157 (Brave,
  driven by chromedriver), including the benchmark, blocked autoplay with
  sound and fullscreen outside a user gesture. Tests that need a local
  `dart:io` HTTP server (disk cache, retry) or device rotation are skipped
  on web. HLS.js, Safari and Firefox have not been run.
