# Offline viewing

Users can download videos and watch them without a network, for example
episodes of a series before a flight. Downloads are off by default and the
app decides who may use them: many apps keep offline viewing for premium
subscribers.

```dart
final downloads = manager.downloads;

// When the app starts, and whenever the subscription changes.
await downloads.setEnabled(user.isPremium);

await downloads.download(
  'coastline-3',                              // your id
  PlayStackSource.network(episode.url),
  title: 'Coastline · Episode 3',             // Android notification
  quality: PlayStackDownloadQuality.medium,   // HLS/DASH: at most 720p
  metadata: {'series': 'Coastline'},          // kept for your downloads screen
);
```

Playing needs nothing else. A source that was downloaded (the same URL,
or the same `cacheKey`) plays from the saved copy, also in a
`PlayStackFeedView` and without a network. Feeds also prepare downloaded
items while the device is offline.

## Quality

Let the user choose how good, and how big, a download is, as streaming
apps do:

| `PlayStackDownloadQuality` | Saves | `label` |
| --- | --- | --- |
| `low` | Up to 360p | `360p` |
| `medium` | Up to 720p | `720p` |
| `high` | Up to 1080p | `1080p` |
| `best` (default) | The best rendition | `Best` |

```dart
final quality = await showModalBottomSheet<PlayStackDownloadQuality>(
  context: context,
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final q in [PlayStackDownloadQuality.low, PlayStackDownloadQuality.medium, PlayStackDownloadQuality.high])
        ListTile(title: Text(q.label), onTap: () => Navigator.pop(context, q)),
    ],
  ),
);
if (quality != null) await downloads.download(id, source, quality: quality);
```

The quality picks the renditions of HLS and DASH streams; on Android a
stream without a rendition that small saves its smallest one. Progressive files (MP4) are
saved as they are. For an exact cap, pass `maxVideoHeight` instead. On iOS
the cap needs iOS 16; iOS 15 saves the best rendition.

## Turning it on and off

`setEnabled` is the switch for the user's right to watch offline:

| | Enabled | Disabled (default) |
| --- | --- | --- |
| New downloads | Start | `download` throws `PlayStackErrorCode.notAllowed` |
| Running downloads | Go on | Pause, and continue when enabled again |
| Saved videos | Play from the device | Stream from the network like any video |
| Files | Kept | Kept |

Call it at every start: PlayStack does not remember it. To delete the files
too, for example when the user signs out, call `removeAll()`.

The downloads belong to the app, not to one manager: every manager and
every `PlayStackFeedView` sees the same downloads and the same switch.

## Progress and managing downloads

```dart
ValueListenableBuilder<List<PlayStackDownload>>(
  valueListenable: manager.downloads.downloads,
  builder: (context, downloads, _) => ListView(
    children: [
      for (final d in downloads)
        ListTile(
          title: Text(d.metadata['series'] ?? d.id),
          subtitle: Text('${d.state.name} ${d.percent?.round() ?? 0}%'),
        ),
    ],
  ),
);

manager.downloads['coastline-3'];            // one download, or null
manager.downloads.forSource(source);         // by source
manager.downloads.isAvailableOffline(source);
await manager.downloads.pause('coastline-3');
await manager.downloads.resume('coastline-3'); // also retries a failure
await manager.downloads.remove('coastline-3');
```

`PlayStackDownload` carries the `state` (`queued`, `downloading`,
`paused`, `completed`, `failed`), `bytesDownloaded`, `totalBytes` and
`percent` when known, the `error` of a failure, and your `title` and
`metadata`. The list updates about once a second while something
downloads.

Starting an id again replaces what was saved under it.

## What is saved

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Progressive files (MP4) | Yes | Yes | No |
| HLS | Yes, the renditions up to `maxVideoHeight` | Yes (`.movpkg`), the renditions up to `maxVideoHeight`; not in the simulator | No |
| DASH | Yes | No (AVFoundation does not play DASH) | No |
| Request headers | Sent | Sent | No |
| In the background | With the download service (below) | Yes, by itself (background `URLSession`) | No |

Only network sources can be downloaded. `isSupported()` is false on the
web.

Files live in the app's private storage (Android `files/playstack_downloads`,
iOS Application Support, excluded from iCloud backup) and are removed with
the app. DRM-protected streams are not supported.

## Platform setup

### Android

Downloads run while the app is open without any setup. To keep them
running in the background, with a progress notification, declare the
download service in `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />

    <application ...>
        <service
            android:name="dev.playstack.android.PlayStackDownloadService"
            android:foregroundServiceType="dataSync"
            android:exported="false">
            <intent-filter>
                <action android:name="androidx.media3.exoplayer.downloadService.action.RESTART" />
                <category android:name="android.intent.category.DEFAULT" />
            </intent-filter>
        </service>
    </application>
</manifest>
```

On Android 13 and later the progress notification shows only when the
app has the `POST_NOTIFICATIONS` permission; downloads run either way.
The notification channel is called "Downloads"; override the
`playstack_download_channel` string resource to rename or translate it.

### iOS

Nothing to configure. Downloads continue while the app is suspended and
finish even if the system ends it; the plugin handles the background
session events. HLS downloads need a real device: the simulator cannot
save HLS streams.
