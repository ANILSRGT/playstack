# Audio

```dart
ReelKitManager(
  config: const ReelKitConfig(
    audio: ReelAudioConfig(
      handleAudioFocus: true,          // Android
      pauseOnAudioRouteLoss: true,     // headphones unplugged
      iosAudioSessionCategory: ReelAudioSessionCategory.playback,
      mixWithOthers: false,            // iOS, with a managed category
      resumeAfterInterruption: true,   // iOS
    ),
  ),
);
```

Audio settings are engine-wide; the first manager that initializes the
engine sets them.

## Android

- An audible player requests audio focus when it plays and pauses when
  another app takes focus (a call, a music app).
- Muted players (`setMuted(true)` or volume 0) never request focus, so a
  muted autoplaying feed does not stop the user's music. Unmuting requests
  focus.
- Unplugging headphones or disconnecting Bluetooth audio pauses.

## iOS

- `unmanaged` (default) leaves the app's `AVAudioSession` alone. The iOS
  default category is silenced by the ring/silent switch.
- `ambient` mixes with other audio and follows the silent switch.
- `playback` (movie playback mode) plays with the silent switch on and
  interrupts other audio, unless `mixWithOthers` is set. It is applied when
  playback first starts, not at initialization, so merely creating a
  manager does not interrupt the user's music.
- Interruptions (calls, alarms, Siri) pause; with
  `resumeAfterInterruption`, playback resumes when the system says it
  should.
- When the audio route goes away (headphones unplugged), AVPlayer pauses
  itself; ReelKit reports it.

Background audio also needs the *Audio* background mode and
`ReelLifecycleConfig(pauseOnBackground: false)`.

## Web

Browsers manage audio themselves. Autoplay with sound is blocked until the
user interacts with the page: `play()` fails with `playbackNotAllowed`.
Start muted and unmute from a tap.

```dart
try {
  await controller.play();
} on ReelKitException catch (error) {
  if (error.code == ReelKitErrorCode.playbackNotAllowed) {
    await controller.setMuted(true);
    await controller.play();
  }
}
```

## Knowing why playback stopped

```dart
controller.interruptions.listen((interruption) {
  switch (interruption.type) {
    case ReelInterruptionType.audioInterruption:
      // another app or the system took audio; ended tells when it is over
    case ReelInterruptionType.audioRouteLost:
      // headphones were unplugged
  }
});
```
