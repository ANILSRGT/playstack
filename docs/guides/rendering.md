# Rendering

`PlayStackVideoView` draws a controller's frames and nothing else: no controls,
no gestures, no progress bar.

```dart
PlayStackVideoView(
  controller: controller,
  fit: BoxFit.cover,                    // any BoxFit
  alignment: Alignment.topCenter,       // any AlignmentGeometry
  backgroundColor: Colors.black,        // letterbox areas
  clipBehavior: Clip.antiAlias,
  borderRadius: BorderRadius.circular(16),
  poster: NetworkImage(post.thumbnailUrl),           // until the first frame
  placeholderBuilder: (context, state) =>            // above the poster
      state.isBuffering ? const CircularProgressIndicator() : const SizedBox(),
  errorBuilder: (context, error) => Center(
    child: TextButton(onPressed: controller.retry, child: Text(error.message)),
  ),
);
```

## Size and rotation

The view sizes the video from `controller.value.videoInfo`: encoded size,
pixel aspect ratio and rotation metadata (for example phone videos
recorded in portrait and stored with a 90° rotation). `fit` and
`alignment` then place that display size in the available space, exactly
like an `Image`.

```dart
// Let the video decide its height in a list.
AspectRatio(
  aspectRatio: controller.value.aspectRatio ?? 16 / 9,
  child: PlayStackVideoView(controller: controller),
);
```

`videoInfo` is kept when a controller loses its native player, so layouts
do not jump while it prepares again.

## What is rendered

| Platform | Mechanism |
| --- | --- |
| Android | Flutter `SurfaceProducer` texture fed by ExoPlayer |
| iOS | `FlutterTexture` backed by `AVPlayerItemVideoOutput` |
| Web | The `<video>` element in a platform view (`HtmlElementView`) |

The first frame of a prepared, paused video is rendered, so a preloaded
feed item shows its picture before it plays.

## Building controls

Rebuild controls from the controller's state; read the position from a
stream that polls only while playing.

```dart
ValueListenableBuilder<PlayStackPlaybackState>(
  valueListenable: controller,
  builder: (context, state, _) => Row(
    children: [
      IconButton(
        icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
        onPressed: state.isPlaying ? controller.pause : controller.play,
      ),
      Expanded(
        child: StreamBuilder<PlayStackPositionSnapshot>(
          stream: controller.positions(),
          builder: (context, snapshot) {
            final total = state.duration?.inMilliseconds ?? 0;
            final now = snapshot.data?.position.inMilliseconds ?? 0;
            return Slider(
              value: total == 0 ? 0 : now.clamp(0, total) / total,
              onChanged: total == 0
                  ? null
                  : (v) => controller.seekTo(
                        Duration(milliseconds: (v * total).round()),
                      ),
            );
          },
        ),
      ),
    ],
  ),
);
```

## Web

One `PlayStackVideoView` per controller at a time: the video is a single
`<video>` element. See [Fullscreen](fullscreen.md#platform-notes).
