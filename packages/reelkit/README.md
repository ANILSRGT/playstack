# reelkit

Native video playback manager for Flutter: a bounded pool of native
players reused by priority, feeds that prepare the next videos within
network, memory and decoder limits, disk caching, fullscreen with
orientation restoration, audio focus and interruptions, automatic retry,
typed errors and a rendering widget with full `BoxFit`/`Alignment`
support. You build the UI.

Engines: AndroidX Media3 ExoPlayer (Android), AVFoundation (iOS) and
`HTMLVideoElement` (web).

```dart
final manager = ReelKitManager();
await manager.initialize();

final feed = manager.createFeed([
  for (final post in posts)
    ReelFeedItem(ReelSource.network(post.url), id: post.id),
]);

PageView.builder(
  scrollDirection: Axis.vertical,
  itemCount: feed.length,
  onPageChanged: feed.setActiveIndex,
  itemBuilder: (context, index) =>
      ReelVideoView(controller: feed.controllerAt(index), fit: BoxFit.cover),
);
feed.setActiveIndex(0);
```

Development preview (0.1.0-dev.7): verified on an Android emulator and an
iOS simulator; web is compiled and unit tested but not yet run in a
browser.

- [Guides](https://github.com/ANILSRGT/reelkit/blob/main/docs/README.md)
- [Platform support](https://github.com/ANILSRGT/reelkit/blob/main/docs/guides/platforms.md)
- [Benchmarks](https://github.com/ANILSRGT/reelkit/blob/main/docs/BENCHMARKS.md)
- [Repository](https://github.com/ANILSRGT/reelkit)
