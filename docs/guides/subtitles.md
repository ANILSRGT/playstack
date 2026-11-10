# Tracks and subtitles

## Listing tracks

```dart
ValueListenableBuilder<List<ReelTrack>>(
  valueListenable: controller.tracks,
  builder: (context, tracks, _) => Column(
    children: [
      for (final track in tracks)
        if (track.type == ReelTrackType.audio)
          ListTile(
            title: Text(track.label ?? track.language ?? track.id),
            trailing: track.isSelected ? const Icon(Icons.check) : null,
            onTap: () => controller.selectTrack(track),
          ),
    ],
  ),
);
```

A `ReelTrack` has a `type` (`audio`, `video`, `text`), an engine-defined
`id`, `isSelected`, and when known `label`, `language` (BCP 47),
`bitrate`, `width`, `height`, `frameRate`, `codecs` and `channelCount`.
Track ids are stable for one source; do not persist them across sources.

## Selecting

```dart
await controller.selectTrack(englishAudio);
await controller.selectTrack(turkishSubtitles);
await controller.selectAutomaticTrack(ReelTrackType.audio); // engine default
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
    ReelVideoView(controller: controller),
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

```dart
// Cap adaptive streams on cellular, for example.
await controller.setVideoQualityLimit(
  const ReelVideoQualityLimit(maxHeight: 720, maxBitrate: 2500000),
);
await controller.setVideoQualityLimit(ReelVideoQualityLimit.none);
```

On Android a specific video track (rendition) can also be selected with
`selectTrack`.

## Platform support

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Audio tracks | Yes | Yes (media selection) | Only where the browser exposes `audioTracks` (Safari) |
| Subtitle tracks and text | In-band, HLS and DASH | Legible media selection | Tracks the browser exposes, for example HLS in Safari; Chromium does not expose in-band MP4 text |
| Video rendition selection | Yes | No: listed for information, AVFoundation chooses | No |
| Quality limit | Yes | Yes (`preferredPeakBitRate`, `preferredMaximumResolution`) | No (`notImplemented`) |

`capabilities.supportsTrackSelection`, `supportsVideoTrackSelection` and
`supportsVideoQualityLimit` report these at run time.
