# reelkit

Native video playback manager for Flutter: a bounded pool of native
players reused by priority, feeds that prepare the next videos within
network, memory and decoder limits, disk caching, fullscreen with
orientation restoration, audio focus and interruptions, automatic retry,
typed errors, a rendering widget with full `BoxFit`/`Alignment`
support, and a ready-made feed view with transitions. You supply the
controls, or keep the default ones.

Engines: AndroidX Media3 ExoPlayer (Android), AVFoundation (iOS) and
`HTMLVideoElement` (web).

```dart
ReelFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  posterUrl: (post) => post.thumbnailUrl,
  onLoadMore: () => api.fetchMorePosts(),
  transition: ReelFeedTransition.stack,
  controlsBuilder: (context, page) =>
      ReelDefaultControls(page: page, child: MyCaption(post: page.data)),
)
```

Development preview (0.1.0-dev.7): verified on an Android emulator, an
iOS simulator and headless Chromium; not yet on physical devices.

- [Guides](https://github.com/ANILSRGT/reelkit/blob/main/docs/README.md)
- [Platform support](https://github.com/ANILSRGT/reelkit/blob/main/docs/guides/platforms.md)
- [Benchmarks](https://github.com/ANILSRGT/reelkit/blob/main/docs/BENCHMARKS.md)
- [Repository](https://github.com/ANILSRGT/reelkit)
