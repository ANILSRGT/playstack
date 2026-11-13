# Installation

## Requirements

| | Minimum |
| --- | --- |
| Flutter | 3.47 |
| Dart | 3.13 |
| Android | API 24 (Android 7.0); compiled against API 36, JDK 17 |
| iOS | 15.0 (CocoaPods or Swift Package Manager) |
| Web | Any browser with `HTMLVideoElement`; Chromium, Firefox and Safari are the targets |

## Add the dependency

Applications depend on `playstack` only. The platform packages
(`playstack_android`, `playstack_ios`, `playstack_web`) are endorsed and are
added automatically.

```yaml
dependencies:
  playstack: ^0.1.0-dev.8
```

or `flutter pub add playstack`. To follow unreleased changes, depend on
the repository instead:

```yaml
dependencies:
  playstack:
    git:
      url: https://github.com/ANILSRGT/playstack
      path: packages/playstack
```

```dart
import 'package:playstack/playstack.dart';
```

## Android

Nothing to configure. The plugin's manifest adds
`android.permission.ACCESS_NETWORK_STATE` (used for network-aware
preloading and reconnection retries). `INTERNET` is already part of every
Flutter app's release manifest.

Cleartext `http://` URLs need a network security configuration in the app,
as for any Android app.

## iOS

Nothing to configure for HTTPS sources. For `http://` URLs add an App
Transport Security exception to `Info.plist`.

If your app plays with the ring/silent switch on, or keeps playing in the
background, set the audio session category (see [Audio](audio.md)) and,
for background audio, enable the *Audio, AirPlay, and Picture in Picture*
background mode.

## Web

Nothing to configure for MP4/WebM. HLS plays natively in Safari; in other
browsers load [HLS.js](https://github.com/video-dev/hls.js) in
`web/index.html` and PlayStack uses it when `window.Hls` exists:

```html
<script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.20/dist/hls.min.js"></script>
```

Browsers cannot send custom HTTP headers for `<video>` sources, cannot
play files from a path and block autoplay with sound before a user
gesture. See [Platform support](platforms.md).

## Verify

```dart
final manager = PlayStackManager();
await manager.initialize();
print(manager.capabilities.engineName);
// AndroidX Media3 ExoPlayer, AVFoundation AVPlayer or HTMLVideoElement
```
