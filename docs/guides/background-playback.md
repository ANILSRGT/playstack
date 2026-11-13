# Media controls and Picture-in-Picture

PlayStack can keep a video going when the user leaves the app, in two ways:

- **Media controls.** The video shows on the lock screen, in the
  notification shade (Android) and in Control Center (iOS), and headphone
  buttons and cars control it. Its sound keeps playing in the background,
  for example while the user listens to a series with the screen off.
- **Picture-in-Picture.** The video moves to a small floating window when
  the user leaves the app, or when a button asks for it.

Both need a few lines of platform setup, described below.

## In a feed

`PlayStackFeedView` does it for the video in view:

```dart
PlayStackFeedView<Episode>(
  items: episodes,
  source: (episode) => episode.source,
  mediaInfo: (episode) => PlayStackMediaInfo(
    title: 'Episode ${episode.number}: ${episode.title}',
    artist: series.title,
    artworkUrl: episode.poster,
  ),
  pictureInPicture: true,
)
```

- `mediaInfo` puts the video in view in the media controls. Swiping
  updates them. The skip buttons move the feed to the next or previous
  item, also while the app is in the background. Return null for items
  that should not appear there.
- `pictureInPicture: true` moves the video in view to the floating window
  when the user leaves the app while it plays.
- `view.startPictureInPicture()` (a `PlayStackFeedViewController`) starts
  it from a button, with or without `pictureInPicture`. It returns false
  where Picture-in-Picture is not available.
- `view.isPictureInPicture` tells whether the window is open.

On Android the floating window shows the whole app, so while it is open the
view shows only the video, without controls. On iOS the system shows the
video itself.

## With your own players

The same features are on the manager:

```dart
// Media controls.
await manager.mediaSession.show(
  controller,
  const PlayStackMediaInfo(title: 'Episode 3', artist: 'Coastline'),
  onNext: playNext,         // optional skip buttons
  onPrevious: playPrevious,
);
await manager.mediaSession.clear();

// Picture-in-Picture.
if (await manager.pictureInPicture.isSupported()) {
  await manager.pictureInPicture.enable(controller); // when leaving the app
  await manager.pictureInPicture.start();            // now, from a button
}
manager.pictureInPicture.isActive;                   // a ValueListenable<bool>
await manager.pictureInPicture.disable();
```

One video at a time each; showing or enabling another replaces it.
Play, pause and the position bar of the media controls act on the
controller.

When the app goes to the background the manager pauses its players
(`PlayStackLifecycleConfig.pauseOnBackground`), except the video in the
media controls and the video in an open Picture-in-Picture window.

## Platform setup

### iOS

Add the `audio` background mode to `ios/Runner/Info.plist`. It is needed
for sound in the background and for Picture-in-Picture:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Picture-in-Picture works on iPhone from iOS 14 and on iPad. It does not
start in the iOS simulator on every version; test it on a device.

### Android

In `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Media controls: playback in the background. -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

    <application ...>
        <activity
            android:name=".MainActivity"
            android:supportsPictureInPicture="true"
            android:resizeableActivity="true"
            ...>
        </activity>

        <!-- Media controls: the notification and playback in the background. -->
        <service
            android:name="dev.playstack.android.PlayStackMediaService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="androidx.media3.session.MediaSessionService" />
            </intent-filter>
        </service>
    </application>
</manifest>
```

- The activity needs `android:configChanges` with
  `screenSize|smallestScreenSize|screenLayout|orientation`, which Flutter
  apps have by default, so it is not recreated when the window opens.
- Without the service the media controls still work while the app is open
  (headphone buttons, Bluetooth), but no notification is shown and the
  video stops in the background.
- Media notifications are exempt from the notification permission of
  Android 13, so no `POST_NOTIFICATIONS` request is needed.
- From Android 12 the window opens with the system's own animation
  (`setAutoEnterEnabled`); before that it opens when the user presses Home.

## Platform support

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Media controls | Media3 `MediaSession`; notification through `PlayStackMediaService` | `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` | No |
| Background sound | With the service declared | With the `audio` background mode | No |
| Picture-in-Picture | Activity Picture-in-Picture mode, API 26+ | `AVPictureInPictureController` | No |
| Automatic start on leaving the app | API 31+: system animation; API 26–30: on Home | Yes | No |
