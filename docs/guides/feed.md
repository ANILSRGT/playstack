# Feeds

A short-video feed is one widget. Give `ReelFeedView` your items and tell
it where each video is:

```dart
ReelFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  posterUrl: (post) => post.thumbnailUrl,   // optional, shown until the first frame
  onLoadMore: () => api.fetchMorePosts(),   // optional, return [] when there are no more
)
```

That is all. The view:

- creates the players when it appears and releases them when it goes
  away
- plays the video in view and prepares the next ones
- loads more items when the user nears the end
- shows default controls: tap to pause, sound, fullscreen for landscape
  videos, progress and retry

For a list of URLs, pass just the list: `ReelFeedView(items: urls)`. For
assets, files or HTTP headers, use `source: (post) => ReelSource...`
instead of `videoUrl`.

Its settings (`ReelKitConfig.reels` and `ReelFeedConfig.reels`) are tuned
for swiping two or three videos a second. They include:

- five videos prepared ahead
- looping
- quality capped to the screen
- fast startup at lower quality, then switching up while playing
- muted autoplay on the web

To change them, pass `manager:` (a `ReelKitManager` with your config) or
`feedConfig:`.

### Updating items

Keep your list in state and pass a new one when it changes:

- A list that starts with the old one appends the new items, so playback
  continues.
- Any other list replaces the feed, for example after pull to refresh.

When items can be reordered or removed, pass `itemId: (post) => post.id`.
Players then follow their items instead of starting over.

## Controls

`controlsBuilder` draws everything above the video. It is called for each
page with a `ReelFeedPage`, which gives you:

- `data`: your item, typed (a `Post` in a `ReelFeedView<Post>`)
- `controller`: the video's `ReelPlayerController`: play, pause, seek, state
- `isActive`: whether this item is the one in view
- `isFullscreen`: whether the view is in fullscreen
- `index`: the item's position
- `view`: a `ReelFeedViewController`: next page, fullscreen, sound

By default the builder is `ReelDefaultControls`:

- tap to pause and resume
- a sound switch that mutes the whole feed
- a fullscreen button on landscape videos
- a thin progress bar
- a buffering indicator that appears only when a wait gets long
- a retry button on errors

The buffering indicator waits 2 s while a frame or poster is on screen.
Until then the picture just holds, like a brief freeze. Over a black
screen it waits 800 ms.

Keep the defaults and add your own layer:

```dart
ReelFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  controlsBuilder: (context, page) => ReelDefaultControls(
    page: page,
    onDoubleTap: () => like(page.data),
    showMuteButton: false, // we draw our own
    child: PostOverlay(post: page.data, controller: page.controller),
  ),
)
```

Taps that your `child` does not handle fall through to tap-to-pause.

Or replace the defaults completely. The parts are public: `ReelProgressBar`,
`ReelBufferingIndicator` and `ReelMuteButton`.

```dart
ReelFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  controlsBuilder: (context, page) => Stack(
    children: [
      MyCaption(post: page.data),
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

By default portrait videos fill the page and landscape videos are shown
whole. Pass `fit:` to use one fit for every video, or `videoBuilder:` to
replace the video layer.

## Direction and transitions

```dart
ReelFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
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

ReelFeedView<Post>(items: posts, videoUrl: (post) => post.videoUrl, controller: view);

await view.nextPage();      // animated with the view's transition
await view.previousPage();
await view.animateTo(10, duration: const Duration(milliseconds: 600));
view.jumpTo(0);
await view.toggleFullscreen();
view.setMuted(true);
view.manager;               // stats, cache, network status
```

Builders also get the controller as `page.view`. The controller is a
`Listenable`: wrap an app bar in a `ListenableBuilder` to hide it in
fullscreen or to show the page number.

Fullscreen turns the screen to match the video and lifts the quality cap.
Swiping is locked, and the back button leaves fullscreen.

To move to the next video when the current one ends, set `autoAdvance:
true`. It needs videos that do not loop:

```dart
manager: ReelKitManager(
  config: ReelKitConfig(player: ReelPlayerConfig(looping: false)),
),
```

## Posters

The view downloads the posters of the next `precachePosters` items
(default 3) ahead of time, so a fast swipe shows a poster rather than
black.

## Managing the feed yourself

`ReelFeedView.feed` shows a `ReelFeedManager` you create and own. This
is for cases where your own code adds, inserts and removes items, or
where several screens share one feed:

```dart
final manager = ReelKitManager(config: ReelKitConfig.reels());
await manager.initialize();
final feed = manager.createFeed(
  [for (final post in posts) ReelFeedItem(ReelSource.network(post.url), id: post.id, data: post)],
  config: ReelFeedConfig.reels,
);

ReelFeedView<Post>.feed(
  feed: feed,
  onEndReached: () => feed.addAll(morePosts()),
)
```

You dispose the feed (or the manager) yourself.

## Item identity

This applies to `ReelFeedView.feed`. Each `ReelFeedItem` has an `id`,
taken from the argument, the source's `id`, or generated. Controllers follow ids. So a playing video keeps
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
