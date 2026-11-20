# Sleep timer and audio only

## Sleep timer

`manager.sleepTimer` pauses playback after a time, fading the sound out
first, like podcast and video apps:

```dart
final timer = manager.sleepTimer;
timer.start(const Duration(minutes: 30));                    // fades out over the last 10 s
timer.start(const Duration(minutes: 15), fadeOut: Duration.zero);
timer.startEndOfVideo();  // stop when the current video ends
timer.extend(const Duration(minutes: 5));
timer.cancel();

timer.isActive;
timer.isEndOfVideo;
timer.remaining;          // Duration?, for a countdown label
timer.onFinished.listen((_) => showSnackBar('Good night'));
```

It is a `ChangeNotifier`; rebuild a menu with `ListenableBuilder`. When it
fires, every video and feed of the manager pauses and volumes return to
what they were. Feeds play again on the user's next play.

PlayStack draws no sleep timer menu; build one with the calls above (the
demo app's player menu is an example).

## Audio only

```dart
await controller.setAudioOnly(true);
controller.audioOnly; // ValueListenable<bool>
```

The picture is no longer decoded and adaptive streams load their smallest
rendition, which saves battery and data, for example for music videos or
podcasts in the background. `PlayStackVideoView` shows the poster
meanwhile. Pass false to bring the picture back.

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Audio only | Video track disabled | Video tracks disabled | The element is hidden; the browser still downloads video |
