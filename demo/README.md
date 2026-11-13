# ReelKit demo

Two small apps built on ReelKit, the way an application would use it.
The launcher (`lib/launcher_page.dart`) opens either one. Each feed is
one `ReelFeedView`; everything else is the app's own UI.

## Reels

| File | Shows |
| --- | --- |
| `lib/reels_page.dart` | `ReelFeedView` with `onLoadMore`, pull to refresh (`onRefresh`), watch time (`onItemViewed`), the stack transition, and a top bar that hides in fullscreen through `ReelFeedViewController` |
| `lib/post_controls.dart` | The app's caption, like and comment buttons and a double-tap heart, layered on `ReelDefaultControls` (tap or hold to pause, sound, fullscreen, seekable progress, retry) |
| `lib/home_page.dart` | Tabs in an `IndexedStack` with `TickerMode`: the feed pauses while its tab is hidden |
| `lib/explore_page.dart`, `lib/author_page.dart` | Grids that open a feed at the tapped video; the feed below pauses under the pushed page |
| `lib/comments_sheet.dart` | A bottom sheet during which the feed is paused with `view.pause()` / `view.resume()` |
| `lib/stats_sheet.dart` | Live pool, preload, start latency, network, cache and watch-time figures |

## Drama

| File | Shows |
| --- | --- |
| `lib/drama/series_page.dart` | A series page: continue where you stopped, or pick any episode |
| `lib/drama/episode_player_page.dart` | Episodes as a vertical feed: `initialIndex`, `startPosition` to continue, `autoAdvance` to the next episode, `onItemViewed` to save the position, an episode list that jumps with `jumpToItem`, hold for 2x |
| `lib/drama/drama_data.dart` | The series and the saved progress |

`lib/catalog.dart` lists the public test media: vertical 9:16 clips and
landscape HLS streams.

```bash
cd demo
flutter run                 # Android or iOS device/simulator
flutter run -d chrome       # web (starts muted: browsers block autoplay with sound)
```
