# Tracks and subtitles

## Listing tracks

```dart
ValueListenableBuilder<List<PlayStackTrack>>(
  valueListenable: controller.tracks,
  builder: (context, tracks, _) => Column(
    children: [
      for (final track in tracks)
        if (track.type == PlayStackTrackType.audio)
          ListTile(
            title: Text(track.label ?? track.language ?? track.id),
            trailing: track.isSelected ? const Icon(Icons.check) : null,
            onTap: () => controller.selectTrack(track),
          ),
    ],
  ),
);
```

A `PlayStackTrack` has a `type` (`audio`, `video`, `text`), an engine-defined
`id`, `isSelected`, and when known `label`, `language` (BCP 47),
`bitrate`, `width`, `height`, `frameRate`, `codecs` and `channelCount`.
Track ids are stable for one source; do not persist them across sources.

## Selecting

```dart
await controller.selectTrack(englishAudio);
await controller.selectTrack(turkishSubtitles);
await controller.selectAutomaticTrack(PlayStackTrackType.audio); // engine default
await controller.disableSubtitles();
```

Selections survive re-preparation (for example after the controller lost
its native player) and are reset by `setSource`.

## Showing subtitles

Engines deliver subtitle text as plain strings; you render it with your
own widgets and style.

```dart
Stack(
  children: [
    PlayStackVideoView(controller: controller),
    Positioned(
      left: 16,
      right: 16,
      bottom: 48,
      child: ValueListenableBuilder<List<String>>(
        valueListenable: controller.subtitles,
        builder: (context, lines, _) => Text(
          lines.join('\n'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            shadows: [Shadow(blurRadius: 4)],
          ),
        ),
      ),
    ),
  ],
);
```

Styling and positioning from the subtitle file are not preserved.

## Video quality

Let the user pick a rendition of an adaptive stream:

```dart
controller.videoQualities;                 // List<PlayStackVideoQuality>, highest first
await controller.setVideoQuality(controller.videoQualities.last); // 360p, say
await controller.setVideoQuality(null);    // back to automatic
controller.videoQuality;                   // ValueListenable<PlayStackVideoQuality?>
```

`videoQualities` has one entry per size (`label` is `720p` style) and is
empty or a single entry for an MP4 file, where there is nothing to choose.
A choice caps the stream at that rendition, so the engine still steps down
when the network cannot keep up. It replaces the app's own limits below
for this video until another source is set. The default feed settings
sheet lists the qualities.

To cap quality for the app instead of the user:

```dart
// Cap adaptive streams on cellular, for example.
await controller.setVideoQualityLimit(
  const PlayStackVideoQualityLimit(maxHeight: 720, maxBitrate: 2500000),
);
await controller.setVideoQualityLimit(PlayStackVideoQualityLimit.none);
```

Changing the limit never interrupts playback: it applies at the next
segment the engine loads, like any adaptive switch. Raising it switches up
once a few seconds are buffered (Android: one segment's worth, 4 s; iOS:
AVFoundation decides); lowering it switches down at the next segment. On
Android the limit is read inside adaptive track selection rather than set
as `TrackSelectionParameters`, which would discard the buffer of HLS and
DASH streams and stall.

On Android a specific video track (rendition) can also be selected with
`selectTrack`.

## Platform support

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Audio tracks | Yes | Yes (media selection) | Only where the browser exposes `audioTracks` (Safari) |
| Subtitle tracks and text | In-band, HLS and DASH | Legible media selection | Tracks the browser exposes, for example HLS in Safari; Chromium does not expose in-band MP4 text |
| Video rendition selection | Yes | No: listed for information, AVFoundation chooses | No |
| User quality choice (`setVideoQuality`) | Yes | Yes (HLS variants, iOS 15+) | No |
| Quality limit | Yes | Yes (`preferredPeakBitRate`, `preferredMaximumResolution`) | No (`notImplemented`) |

`capabilities.supportsTrackSelection`, `supportsVideoTrackSelection` and
`supportsVideoQualityLimit` report these at run time.
