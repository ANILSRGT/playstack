# Chromecast and AirPlay

## AirPlay (iOS)

`PlayStackAirPlayButton` is the system's AirPlay button, in the core
package. A tap lists Apple TVs and AirPlay speakers; the playing video
moves there and the app keeps controlling it (play, pause, seek).

```dart
Row(children: [
  const PlayStackAirPlayButton(),        // nothing on Android and web
  PlayStackCastButton(onConnected: ...), // package:playstack_cast
])
```

`size`, `color` and `activeColor` style it. `PlayStackAirPlayButton.isSupported`
tells whether it shows. Protected (FairPlay) streams are mirrored by the
system.

## Chromecast

Chromecast lives in a separate package, `playstack_cast`, so apps that do
not cast do not ship the Google Cast SDK.

```yaml
dependencies:
  playstack: ^0.1.0-dev.9
  playstack_cast: ^0.1.0-dev.1
```

### Setup

- **Android:** nothing to declare; the plugin brings its Cast options. The
  device needs Google Play services.
- **iOS:** add the local network description and the Bonjour services to
  `Info.plist`:

  ```xml
  <key>NSLocalNetworkUsageDescription</key>
  <string>Finds Cast devices on your network.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_googlecast._tcp</string>
    <string>_CC1AD845._googlecast._tcp</string>
  </array>
  ```

  `CC1AD845` is the default media receiver; with your own receiver, use
  its id there and call `PlayStackCast.setReceiverApplicationId('ABCD1234')`
  before anything else.

The default media receiver plays MP4, HLS and DASH.

### The button

```dart
PlayStackCastButton(
  onConnected: () => PlayStackCast.instance.castController(
    page.controller,
    info: PlayStackMediaInfo(title: episode.title, artworkUrl: episode.poster),
  ),
)
```

The button is hidden while no device is found (`showWhenNoDevices: true`
shows it disabled), grey while disconnected and filled while connected. A
tap opens the device list, or the connected device's controls.

`castController` sends the video to the device at its current position and
pauses it on the phone. When casting stops, or the device disconnects, the
phone continues where the device was.

### Remote control

```dart
final cast = PlayStackCast.instance;
cast.state;       // ValueListenable<PlayStackCastState>: unavailable, noDevices, notConnected, connecting, connected
cast.deviceName;  // "Living Room TV"
cast.playback;    // ValueListenable<PlayStackCastPlayback>: isPlaying, isBuffering, position, duration
await cast.play();
await cast.pause();
await cast.seekTo(const Duration(minutes: 3));
await cast.setVolume(0.5);
await cast.stopCasting();  // back to the phone
await cast.disconnect();
await cast.load(source, info: info, position: Duration.zero); // any network source
```

Only network sources can be cast, and HTTP headers are not sent: the
device downloads the video itself. Protected streams need a receiver of
your own with the license setup.

### Notes

- `playstack_cast` supports Android and iOS. On iOS it uses CocoaPods
  (`google-cast-sdk`); Swift Package Manager is not supported yet.
- Simulators and emulators find no Cast devices; test on a device on the
  same network as a Chromecast.
