# Feeds

A short-video feed takes two objects:

- `ReelFeedManager` holds the items and their players. It plays the item
  in view and prepares the items around it, within pool, network and
  memory limits.
- `ReelFeedView` shows the feed. It handles paging, swipe direction,
  transitions, activation, posters and endless loading. You supply the
  controls, or keep the default ones.

```dart
final manager = ReelKitManager();
await manager.initialize();

final feed = manager.createFeed([
  for (final post in posts)
    ReelFeedItem(
      ReelSource.network(post.videoUrl),
      id: post.id,
      poster: NetworkImage(post.thumbnailUrl),
      data: post,
    ),
]);

ReelFeedView(
  feed: feed,
  onEndReached: () async => feed.addAll(await loadMore()),
);
```

The view never disposes the feed. Dispose the feed or its manager when the
screen closes.

## Controls

`controlsBuilder` draws everything above the video. It is called for each
page with a `ReelFeedPage`, which gives you:

- `item`: the feed item
- `data`: your object, from `ReelFeedItem.data`
- `index`: the item's position in the feed
- `controller`: the item's `ReelPlayerController`
- `isActive`: whether this item is the one in view
- `feed`: the `ReelFeedManager`
- `view`: a `ReelFeedViewController`, to move the view

By default the builder is `ReelDefaultControls`:

- tap to pause and resume
- a sound switch that mutes the whole feed (`feed.setMuted`)
- a thin progress bar
- a buffering indicator that appears only when a wait gets long
- a retry button on errors

The buffering indicator waits 2 s while a frame or poster is on screen.
Until then the picture just holds, like a brief freeze. Over a black
screen it waits 800 ms.

Keep the defaults and add your own layer:

```dart
ReelFeedView(
  feed: feed,
  controlsBuilder: (context, page) => ReelDefaultControls(
    page: page,
    onDoubleTap: () => like(page.data as Post),
    showMuteButton: false, // we draw our own
    child: PostOverlay(post: page.data as Post, controller: page.controller),
  ),
)
```

Taps that your `child` does not handle fall through to tap-to-pause.

Or replace the defaults completely. The parts are public: `ReelProgressBar`,
`ReelBufferingIndicator` and `ReelMuteButton`.

```dart
ReelFeedView(
  feed: feed,
  controlsBuilder: (context, page) => Stack(
    children: [
      MyCaption(post: page.data as Post),
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: ReelProgressBar(controller: page.controller, active: page.isActive),
      ),
      ReelBufferingIndicator(controller: page.controller, active: page.isActive),
    ],
  ),
)
```

Pass `controlsBuilder: null` for no controls at all.

`videoBuilder` replaces the video layer. By default it is a `ReelVideoView`
with `fit` (default `BoxFit.cover`) and the item's poster. Use it to choose
the fit per video:

```dart
videoBuilder: (context, page) => ReelVideoView(
  controller: page.controller,
  fit: (page.data as Post).isLandscape ? BoxFit.contain : BoxFit.cover,
  poster: page.item.poster,
),
```

## Direction and transitions

```dart
ReelFeedView(
  feed: feed,
  scrollDirection: Axis.horizontal, // stories, carousels
  reverse: true,                    // next item from the left (or above)
  transition: ReelFeedTransition.stack,
)
```

Built-in transitions:

| Transition | Effect |
| --- | --- |
| `slide` (default) | Pages slide together |
| `parallax` | The current page moves at half speed; the next slides over it |
| `stack` | The current page stays, shrinks and darkens; the next slides over it like a card |
| `fade` | Pages stay in place and cross-fade |
| `zoom` | The next page grows in while fading in; the current one fades out |
| `cube` | Pages turn like the faces of a cube |

Transitions follow the finger while the user drags. Moves made from code
use the same transition.

To write your own transition, use `details.offset`. It is the page's
position in pages: 0 in view, -1 one page before, 1 one page after.
`details.hold` is the translation that cancels the scroll, so the page
stays where it is:

```dart
transition: ReelFeedTransition.custom((context, details, child) {
  final t = details.offset.abs().clamp(0.0, 1.0);
  return Transform.translate(
    offset: details.offset < 0 ? details.hold * 0.7 : Offset.zero,
    child: Opacity(opacity: 1 - t * 0.5, child: child),
  );
}),
```

## Moving from code

```dart
final view = ReelFeedViewController();

ReelFeedView(feed: feed, controller: view);

await view.nextPage();      // animated, with transitionDuration and transitionCurve
await view.previousPage();
await view.animateTo(10, duration: const Duration(milliseconds: 600));
view.jumpTo(0);
```

Builders also get the controller as `page.view`.

To move to the next video when the current one ends, set `autoAdvance:
true`. It needs videos that do not loop
(`ReelPlayerConfig(looping: false)`).

Lock swiping with `physics: const NeverScrollableScrollPhysics()`, for
example in fullscreen.

## Endless feeds

`onEndReached` is called when the user is `endReachedThreshold` items
(default 3) from the end, once per feed length. Append the next page
there.

The view also downloads the posters of the next `precachePosters` items
(default 3) ahead of time, so a fast swipe shows a poster rather than
black.

## Item identity

Each `ReelFeedItem` has an `id`, taken from the argument, the source's
`id`, or generated. Controllers follow ids. So a playing video keeps
playing, and `ReelFeedView` keeps it on screen, when items are inserted or
removed above it.

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
feed.pause();          // another route covers the feed
feed.resume();         // plays the active item again
feed.setMuted(true);   // every item, including ones added later
feed.activeController; // controller of the item in view
feed.activeIndex;      // ValueListenable<int?>
feed.dispose();        // or manager.dispose()
```

With `autoplay: false`, the feed prepares the active item but does not play
it. Call `feed.activeController?.play()` yourself.

## Your own scroll view

`ReelFeedView` is optional. A `ListView`, a grid or any custom scroll view
can drive a feed directly:

- render `feed.controllerAt(index)` with a `ReelVideoView`
- call `feed.setActiveIndex` with the item that is most visible

```dart
PageView.builder(
  itemCount: feed.length,
  onPageChanged: feed.setActiveIndex,
  itemBuilder: (context, index) =>
      ReelVideoView(controller: feed.controllerAt(index), fit: BoxFit.cover),
);
feed.setActiveIndex(0);
```

## Statistics

```dart
final stats = feed.stats;
print('hit rate ${(stats.preloadHitRate * 100).round()}%, '
    'average start ${stats.averageStartLatency?.inMilliseconds} ms, '
    '${stats.preloadsCancelled} preloads cancelled');
```

`feed.preloadWindow` shows the window applied after limits. See
[Preloading](preloading.md) for how the window is chosen.

## Endless feeds and memory

When more than `controllerRetention` (20) controllers exist, controllers of
items far from the active one are disposed. `controllerAt` recreates them
on demand, so an endless feed keeps a flat memory profile. If you keep
appending for a long session, remove items the user can no longer reach.
