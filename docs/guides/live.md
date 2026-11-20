# Live streams

Live HLS (and DASH on Android) streams play like any other source:

```dart
PlayStackSource.network('https://cdn.example.com/live/channel.m3u8');
```

`controller.value.videoInfo?.isLive` tells that a stream is live.

## Default controls

`PlayStackDefaultControls` shows a `PlayStackLiveBadge` at the top left of
live streams and hides the progress bar, as a live stream has no fixed
length. The badge is red at the live edge and grey with how far behind
("LIVE  -0:42") after the user paused. A tap returns to live.
`showLiveBadge: false` hides it; place `PlayStackLiveBadge` in your own
controls:

```dart
PlayStackLiveBadge(
  controller: page.controller,
  active: page.isActive,
  label: 'CANLI',
  liveColor: Colors.red,
  tolerance: const Duration(seconds: 6), // closer than this counts as live
)
```

## Position and the DVR window

```dart
final position = await controller.getPosition();
position.windowStart;  // the earliest point the user can go back to
position.liveEdge;     // the live point
position.behindLive;   // how far behind live
await controller.seekToLiveEdge();
```

`seekTo` moves inside the window on streams that keep one (DVR).

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Live HLS | Yes | Yes | Safari, or HLS.js |
| Live DASH | Yes | No | No |
| Window, live edge | Yes | Yes (`seekableTimeRanges`) | Yes (`seekable`) |
| `seekToLiveEdge` | Yes | Yes | Yes |

## Trying it

The demo app has a Live screen (launcher, "Live") with two public test
channels. Unified Streaming's
`https://demo.unified-streaming.com/k8s/live/stable/live.isml/.m3u8` runs
around the clock with a DVR window.
