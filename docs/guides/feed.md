# Feeds

A short-video feed is one widget. Give `PlayStackFeedView` your items and tell
it where each video is:

```dart
PlayStackFeedView<Post>(
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
- pauses while a route covers it or its tab is not shown, and while the
  app is in the background
- shows default controls: tap to pause, hold to pause, sound, fullscreen
  for landscape videos, a progress bar you can drag, and retry

For a list of URLs, pass just the list: `PlayStackFeedView(items: urls)`. For
assets, files or HTTP headers, use `source: (post) => PlayStackSource...`
instead of `videoUrl`.

Its settings (`PlayStackConfig.reels` and `PlayStackFeedConfig.reels`) are tuned
for swiping two or three videos a second. They include:

- five videos prepared ahead
- looping
- quality capped to the screen
- fast startup at lower quality, then switching up while playing
- muted autoplay on the web

To change them, pass `manager:` (a `PlayStackManager` with your config) or
`feedConfig:`.

### Updating items

Keep your list in state and pass a new one when it changes:

- A list that starts with the old one appends the new items, so playback
  continues.
- Any other list replaces the feed, for example after pull to refresh.

When items can be reordered or removed, pass `itemId: (post) => post.id`.
Players then follow their items instead of starting over.

### Pull to refresh

Pull to refresh is off until you pass `onRefresh`. Return the new items;
they replace the feed and the view goes back to the first one:

```dart
PlayStackFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  onRefresh: () => api.fetchPosts(page: 0),
)
```

It works on vertical feeds that are not reversed.

### Pausing

The view pauses itself while it cannot be seen:

- a full-screen route is pushed over it
- it is in a tab that is not shown (`TabBarView`, `CupertinoTabScaffold`,
  go_router's `StatefulShellRoute`)
- the app is in the background

It plays again when it is visible. A plain `IndexedStack` does not tell
hidden children they are hidden; wrap each child in
`TickerMode(enabled: isSelected, child: ...)`. Pass `pauseWhenHidden:
false` to keep playing under routes.

Dialogs and bottom sheets leave the feed visible, so the video keeps
playing under them. To stop it there, for example while a comment sheet
is open:

```dart
view.pause();
await showModalBottomSheet(context: context, builder: (_) => Comments());
view.resume();
```

### Watch time

`onItemViewed` is called when the user leaves an item, with how long the
video played and whether it was watched to the end:

```dart
onItemViewed: (view) {
  if (view.watchTime > const Duration(seconds: 3)) api.countView(view.data.id);
  analytics.log('watched', {
    'post': view.data.id,
    'fraction': view.watchedFraction,
    'completed': view.completed,
  });
},
```

Only playing time counts: paused, loading and background time do not.
Items skipped before they started are reported with zero watch time.

### Pages without video

Mix ads, photo posts or "people to follow" cards into the feed. Return
null from `videoUrl` (or `source`) for those items, and build them with
`pageBuilder`:

```dart
PlayStackFeedView<FeedEntry>(
  items: entries,
  videoUrl: (entry) => entry is VideoPost ? entry.url : null,
  pageBuilder: (context, entry, isActive) => AdCard(ad: entry as Ad),
  controlsBuilder: (context, page) => VideoControls(page: page.cast<VideoPost>()),
)
```

These pages take no player and are never preloaded; the videos after them
are prepared while the card is in view. A page can scroll on its own (a
`ListView` taller than the screen): the list scrolls first, and once it
is at its end, pulling on moves the feed to the next or previous page. `isActive` tells whether the page
is the one in view, for example to count an ad impression. `page.cast<R>()`
types `page.data` for the video controls of a mixed feed.

### Locked items

Lock videos the user has not unlocked yet, such as paid episodes:

```dart
PlayStackFeedView<Episode>(
  items: episodes,
  videoUrl: (episode) => episode.url,
  isLocked: (episode) => !purchases.contains(episode.id),
  lockedBuilder: (context, episode, isActive) => Paywall(episode: episode),
)
```

A locked item is never prepared or played. Its page shows its poster
with `lockedBuilder` on top (a lock icon without one). `isLocked` is asked
again on every rebuild: after a purchase, call `setState` and the episode
starts playing. `autoAdvance` stops at a locked episode. With
`PlayStackFeedView.feed`, use `PlayStackFeedItem(locked: true)` and
`feed.setLocked(id, false)`.

### Preparing before the screen opens

Start preparing a feed on the splash screen, so the first video plays
the moment the feed appears:

```dart
// Splash screen, while the app loads:
final reels = PlayStackFeedPreload<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  posterUrl: (post) => post.thumbnailUrl,
);
await reels.ready;   // optional: hold the splash until the first video is ready

// Reels screen:
PlayStackFeedView<Post>.preloaded(reels, onLoadMore: api.fetchMorePosts)
```

The preload starts the engine, prepares the first `count` videos (2 by
default) without playing them and downloads their posters. A preload is
shown by one view, once; that view takes over its players. If the feed is
never opened, call `reels.dispose()`.

### Series and episodes

For a series, continue each episode where the user stopped and let them
jump to any episode:

```dart
PlayStackFeedView<Episode>(
  items: series.episodes,
  videoUrl: (episode) => episode.url,
  controller: view,
  initialIndex: series.episodes.indexOf(tapped),     // open at an episode
  startPosition: (episode) => progress[episode.id],  // continue there
  onItemViewed: (view) => progress[view.data.id] = view.position,
  autoAdvance: true,                                 // next episode when one ends
)

view.jumpToItem(series.episodes[7]);  // from an episode list
```

`startPosition` prepares the video at that point, so it does not show the
beginning first. `PlayStackItemView.position` is where playback was when the
user left; it is null when the video never played. A point in the last
second of a video starts it over.

For a single player, set `controller.startPosition` or pass
`startPosition:` to `manager.createController`.

## Controls

`controlsBuilder` draws everything above the video. It is called for each
page with a `PlayStackFeedPage`, which gives you:

- `data`: your item, typed (a `Post` in a `PlayStackFeedView<Post>`)
- `controller`: the video's `PlayStackPlayerController`: play, pause, seek, state
- `isActive`: whether this item is the one in view
- `isFullscreen`: whether the view is in fullscreen
- `index`: the item's position
- `view`: a `PlayStackFeedViewController`: next page, fullscreen, sound

By default the builder is `PlayStackDefaultControls`:

- tap to pause and resume
- a settings button with playback speed (0.5x to 2x) and subtitle tracks
  (`showSettingsButton`, `playbackSpeeds`); the sheet is
  `PlayStackSettingsSheet.show(context, controller: ...)` for your own
  controls
- subtitle text while a subtitle track is on (`showSubtitles`;
  `PlayStackSubtitles` on its own)
- hold to pause until the finger lifts (`holdAction:
  PlayStackHoldAction.speedUp` plays 2x instead, `PlayStackHoldAction.none` turns it
  off)
- a sound switch that mutes the whole feed
- a fullscreen button on landscape videos
- a thin progress bar; drag along it or tap it to move in the video
  (`seekable: false` turns this off)
- a buffering indicator that appears only when a wait gets long
- a retry button on errors

The buffering indicator waits 2 s while a frame or poster is on screen.
Until then the picture just holds, like a brief freeze. Over a black
screen it waits 800 ms.

Keep the defaults and add your own layer:

```dart
PlayStackFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  controlsBuilder: (context, page) => PlayStackDefaultControls(
    page: page,
    onDoubleTap: () => like(page.data),
    showMuteButton: false, // we draw our own
    child: PostOverlay(post: page.data, controller: page.controller),
  ),
)
```

Buttons in your `child` react at once, even with `onDoubleTap` set. Taps on
empty parts of it fall through to tap to pause, double tap and hold.

Or replace the defaults completely. The parts are public: `PlayStackProgressBar`,
`PlayStackBufferingIndicator`, `PlayStackMuteButton`, `PlayStackSubtitles` and
`PlayStackSettingsSheet`.

```dart
PlayStackFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  controlsBuilder: (context, page) => Stack(
    children: [
      MyCaption(post: page.data),
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: PlayStackProgressBar(controller: page.controller, active: page.isActive),
      ),
      PlayStackBufferingIndicator(controller: page.controller, active: page.isActive),
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
PlayStackFeedView<Post>(
  items: posts,
  videoUrl: (post) => post.videoUrl,
  scrollDirection: Axis.horizontal, // stories, carousels
  reverse: true,                    // next item from the left (or above)
  transition: PlayStackFeedTransition.stack,
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
transition: PlayStackFeedTransition.custom((context, details, child) {
  final t = details.offset.abs().clamp(0.0, 1.0);
  return Transform.translate(
    offset: details.offset < 0 ? details.hold * 0.7 : Offset.zero,
    child: Opacity(opacity: 1 - t * 0.5, child: child),
  );
}),
```

## Moving from code

```dart
final view = PlayStackFeedViewController();

PlayStackFeedView<Post>(items: posts, videoUrl: (post) => post.videoUrl, controller: view);

await view.nextPage();      // animated with the view's transition
await view.previousPage();
await view.animateTo(10, duration: const Duration(milliseconds: 600));
view.jumpTo(0);
view.jumpToItem(post);      // by your object; animateToItem animates
view.indexOfItem(post);     // -1 when not in the feed
await view.toggleFullscreen();
view.setMuted(true);
view.pause();               // until resume(), for example under a sheet
view.resume();
view.manager;               // stats, cache, network status
```

Builders also get the controller as `page.view`. The controller is a
`Listenable`: wrap an app bar in a `ListenableBuilder` to hide it in
fullscreen or to show the page number.

Fullscreen turns the screen to match the video and lifts the quality cap.
Swiping is locked, and the back button leaves fullscreen.

To move to the next video when the current one ends, set `autoAdvance:
true`. The view then stops looping its videos. If you pass your own
manager, start from the reels preset without looping:

```dart
manager: PlayStackManager(config: PlayStackConfig.reels(looping: false)),
```

## Posters

The view downloads the posters of the next `precachePosters` items
(default 3) ahead of time, so a fast swipe shows a poster rather than
black.

## Managing the feed yourself

`PlayStackFeedView.feed` shows a `PlayStackFeedManager` you create and own. This
is for cases where your own code adds, inserts and removes items, or
where several screens share one feed:

```dart
final manager = PlayStackManager(config: PlayStackConfig.reels());
await manager.initialize();
final feed = manager.createFeed(
  [for (final post in posts) PlayStackFeedItem(PlayStackSource.network(post.url), id: post.id, data: post)],
  config: PlayStackFeedConfig.reels,
);

PlayStackFeedView<Post>.feed(
  feed: feed,
  onEndReached: () => feed.addAll(morePosts()),
)
```

You dispose the feed (or the manager) yourself.

## Item identity

This applies to `PlayStackFeedView.feed`. Each `PlayStackFeedItem` has an `id`,
taken from the argument, the source's `id`, or generated. Controllers follow ids. So a playing video keeps
playing, and `PlayStackFeedView` keeps it on screen, when items are inserted or
removed above it.

```dart
feed.addAll(nextPage);                         // endless feed
feed.insert(0, PlayStackFeedItem(source, id: 'new'));
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

`PlayStackFeedView` is optional. A `ListView`, a grid or any custom scroll view
can drive a feed directly:

- render `feed.controllerAt(index)` with a `PlayStackVideoView`
- call `feed.setActiveIndex` with the item that is most visible

```dart
PageView.builder(
  itemCount: feed.length,
  onPageChanged: feed.setActiveIndex,
  itemBuilder: (context, index) =>
      PlayStackVideoView(controller: feed.controllerAt(index), fit: BoxFit.cover),
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
