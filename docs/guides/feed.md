# Feeds

`ReelFeedManager` drives a list of videos shown by any scrolling widget:
you tell it which item is in view, it plays that item and prepares the
ones around it within the pool, network and memory limits.

```dart
final feed = manager.createFeed(
  [for (final post in posts) ReelFeedItem(ReelSource.network(post.url), id: post.id)],
  config: const ReelFeedConfig(preloadAhead: 2, preloadBehind: 1),
);

PageView.builder(
  scrollDirection: Axis.vertical,
  itemCount: feed.length,
  onPageChanged: feed.setActiveIndex,
  itemBuilder: (context, index) => ReelVideoView(
    controller: feed.controllerAt(index),
    fit: BoxFit.cover,
  ),
);

feed.setActiveIndex(0); // once the first item is in view
```

`PageView` is only an example; with a `ListView` or a custom scroll view,
call `setActiveIndex` with the item that is most visible.

## Item identity

Each `ReelFeedItem` has an `id` (from the argument, the source's `id`, or
generated). Controllers follow ids, so a playing video keeps playing when
items are inserted or removed above it.

```dart
feed.addAll(nextPage);                         // endless feed
feed.insert(0, ReelFeedItem(source, id: 'new'));
feed.remove('post-17');                        // or removeAt(index)
feed.updateSource('post-18', betterSource);    // same item, new URL
feed.replaceAll(refreshed);                    // pull to refresh
final index = feed.indexOf('post-20');
```

## Playback control

```dart
feed.pause();   // another route covers the feed
feed.resume();  // plays the active item again
feed.activeController;           // controller of the item in view
feed.activeIndex;                // ValueListenable<int?>
feed.dispose();                  // or manager.dispose()
```

With `autoplay: false` the feed prepares the active item but does not play
it; call `feed.activeController?.play()` yourself.

## Statistics

```dart
final stats = feed.stats;
print('hit rate ${(stats.preloadHitRate * 100).round()}%, '
    'average start ${stats.averageStartLatency?.inMilliseconds} ms, '
    '${stats.preloadsCancelled} preloads cancelled');
```

`feed.preloadWindow` shows the window currently applied after limits. How
the window is chosen: [Preloading](preloading.md).

## Endless feeds and memory

Controllers of items far from the active one are disposed once more than
`controllerRetention` (20) exist and recreated by `controllerAt` on demand,
so an endless feed keeps a flat memory profile. Remove items the user can
no longer reach if you keep appending for a long session.
