# playstack_cast

Chromecast for [PlayStack](https://pub.dev/packages/playstack): a Cast
button, the device picker, and playback of PlayStack videos on Google Cast
receivers with the phone as the remote.

A separate package, so apps that do not cast do not ship the Google Cast
SDK. AirPlay is in `playstack` itself (`PlayStackAirPlayButton`).

## Install

```yaml
dependencies:
  playstack: ^0.1.0
  playstack_cast: ^0.1.0
```

| | Minimum |
| --- | --- |
| Android | API 24, Google Play services on the device |
| iOS | 15.0, CocoaPods (Swift Package Manager is not supported yet) |

**Android:** nothing to declare; the plugin brings its Cast options.

**iOS:** add to `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Finds Cast devices on your network.</string>
<key>NSBonjourServices</key>
<array>
  <string>_googlecast._tcp</string>
  <string>_CC1AD845._googlecast._tcp</string>
</array>
```

`CC1AD845` is Google's default media receiver, which plays MP4, HLS and
DASH. With your own receiver, put its id there and call
`PlayStackCast.setReceiverApplicationId('ABCD1234')` before anything else.

## Use

```dart
import 'package:playstack_cast/playstack_cast.dart';

// In your controls: hidden until a device is found.
PlayStackCastButton(
  onConnected: () => PlayStackCast.instance.castController(
    page.controller,
    info: PlayStackMediaInfo(title: episode.title, artworkUrl: episode.poster),
  ),
)
```

`castController` sends the video to the device at its current position and
pauses it on the phone. When casting stops or the device disconnects, the
phone continues where the device was.

```dart
final cast = PlayStackCast.instance;
cast.state;     // unavailable, noDevices, notConnected, connecting, connected
cast.playback;  // isPlaying, isBuffering, position, duration
await cast.pause();
await cast.seekTo(const Duration(minutes: 3));
await cast.stopCasting();   // back to the phone
```

Only network sources can be cast; HTTP headers are not sent, as the
device downloads the video itself. Simulators and emulators find no
devices: test on a phone on the same network as a Chromecast.

More: [Chromecast and AirPlay guide](https://github.com/ANILSRGT/playstack/blob/main/docs/guides/cast.md).
