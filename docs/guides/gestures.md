# Gestures and scrub preview

`PlayStackDefaultControls` has video app gestures. Each is off until you
turn it on, so a feed only does what you choose.

```dart
controlsBuilder: (context, page) => PlayStackDefaultControls(
  page: page,
  doubleTapToSeek: const Duration(seconds: 10),
  horizontalDragToSeek: true,
  dragGestures: PlayStackDragGestures.fullscreen,
  thumbnails: PlayStackThumbnails.frames(page.controller.source),
),
```

## Double tap to jump

`doubleTapToSeek` jumps back on a double tap on the left third of the
video and forward on the right third, with a "-10 s / +10 s" badge. Keep
tapping the same side to jump again. With `onDoubleTap` set too (a like),
the middle third calls it.

## Drag sideways to seek

`horizontalDragToSeek: true` moves in the video when the user drags
sideways anywhere on it, like short-video apps. The progress bar grows and
shows the preview while the finger moves; the video jumps when it lifts.
The whole width spans the whole video.

The thin bar at the bottom edge is hard to hit next to the system's home
gesture, so turn this on in reels. It is off in horizontal feeds (where
sideways drags move to the next video) except in fullscreen, and on live
streams.

The bar itself can still be dragged or tapped (`seekable`); its touch area
is 36 px tall.

## Brightness and volume

`dragGestures` lets vertical drags change the brightness (left half) and
the volume (right half), with a level indicator:

| | |
| --- | --- |
| `PlayStackDragGestures.off` | Never (default) |
| `PlayStackDragGestures.fullscreen` | Only in fullscreen, where swiping does not move the feed |
| `PlayStackDragGestures.always` | Everywhere; only for horizontal feeds and single players |

The brightness returns to the system's when fullscreen ends.
`manager.getScreenBrightness()` and `setScreenBrightness(value)` (null
restores) are there for your own gestures. Simulators keep their
brightness; check on a device.

## Scrub preview

While the progress bar is dragged, a preview floats above the finger: the
time, and an image when `thumbnails` is set.

| | |
| --- | --- |
| `PlayStackThumbnails.frames(source)` | Frames read from the video itself; nothing to prepare. MP4 and files on Android and iOS |
| `PlayStackThumbnails.webVtt(url)` | A WebVTT thumbnail track (`sprite.jpg#xywh=...`), as most encoders and video hosts produce. Works everywhere, also for HLS |
| `PlayStackThumbnails.sprite(image:, columns:, rows:, interval:)` | One sprite sheet |
| `PlayStackThumbnails.builder((position) => ...)` | Your own: an image URL per position from your server or CDN |

`frames` reads one frame every `interval` (5 s by default) at most
`maxWidth` pixels wide (240), nearest first while the user drags, and keeps
them for the next drag. HLS, DASH, protected streams and the web have no
frames to read; they show the time only. Give those a WebVTT track, or a
`builder` if your host serves stills by time:

```dart
PlayStackThumbnails.builder(
  (position) => PlayStackThumbnail(
    NetworkImage('https://image.mux.com/$id/thumbnail.jpg?time=${position.inSeconds}&width=240'),
  ),
)
```

`manager.getVideoFrame(source, position)` returns a single frame as JPEG
bytes, for covers and your own previews.

Replace the preview with `scrubPreviewBuilder`:

```dart
scrubPreviewBuilder: (context, position, thumbnail) => PlayStackScrubPreview(
  position: position,
  thumbnail: thumbnail,
  thumbnailSize: const Size(90, 160), // portrait videos
),
```

or any widget of your own. `PlayStackProgressBar` takes the same
`thumbnails`, `showScrubPreview` and `scrubPreviewBuilder` in your own
controls, and `scrubValue` to drive its drag from a gesture of yours.

## Debug panel

`showDebugInfo: true` shows a `PlayStackDebugOverlay`: state, size,
bitrate, codec, position, buffer, startup timings, the content id and the
player pool. For development:

```dart
PlayStackDefaultControls(page: page, showDebugInfo: kDebugMode),

// With your own player:
PlayStackDebugOverlay(controller: controller, manager: manager)
```
