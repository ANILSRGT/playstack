# Examples

The example app in `packages/playstack/example` shows every feature with UI
built by the app, as PlayStack expects.

```bash
cd packages/playstack/example
flutter run            # add --profile for realistic performance
```

| Page | Shows |
| --- | --- |
| Single player (`lib/pages/player_page.dart`) | Custom controls, seek bar from `positions()`, speed, loop, mute, audio and subtitle track menu, subtitle text overlay, source switching, error display, fullscreen with `matchVideo` |
| Vertical feed (`lib/pages/feed_page.dart`) | `PlayStackFeedView` from a list of URLs, the default controls plus a label, endless paging with `onLoadMore`, live preload and latency stats from the view controller |
| Player grid (`lib/pages/grid_page.dart`) | Four controllers, exclusive or concurrent playback |
| Diagnostics (`lib/pages/diagnostics_page.dart`) | Capabilities, pool usage per priority, creating and disposing controllers, trimming idle players |
| Benchmark (`lib/pages/benchmark_page.dart`) | Start latency, preloading, rapid scrolling and memory on the device; results as JSON |

## Demo app

`demo/` holds two small apps built the way an application would use
PlayStack, behind a launcher. All of their UI is app code on top of
`PlayStackFeedView`.

Drama: a series page with continue watching and an episode grid, and a
player that opens at an episode (`initialIndex`), continues where the
user stopped (`startPosition`, `PlayStackItemView.position`), moves to the next
episode on its own (`autoAdvance`) and jumps from an episode list
(`jumpToItem`).

Reels:

- an endless home feed with `onLoadMore` and pull to refresh
  (`onRefresh`)
- the app's caption, like and comment buttons and a double-tap heart on
  `PlayStackDefaultControls`
- a comments sheet that pauses the feed with `PlayStackFeedViewController`
- an author page and an explore grid that open feeds at a tapped video;
  the feed pauses under them and in the hidden tab by itself
- watch time from `onItemViewed`, and a stats sheet with pool, preload,
  latency, network and cache figures

It plays public test media (vertical 9:16 reels and landscape HLS test
streams) and loads HLS.js on the web.

```bash
cd demo
flutter run
```

## Integration tests

`packages/playstack/example/integration_test` runs against the real engines:

| File | Covers |
| --- | --- |
| `foundation_test.dart` | Engine initialization and capabilities |
| `playback_test.dart` | Preparation, first frame while paused, rotation, completion, pause, loop, seek, volume, speed, memory source, missing source, pooled source switching, 100-source churn |
| `player_api_test.dart` | Metadata, audio and subtitle tracks with text, source replacement, stop, position stream, quality limit, lifecycle |
| `player_manager_test.dart` | Exclusive and concurrent playback, memory pressure, disposing mid-preparation |
| `feed_test.dart` | Feed playback with a prepared next item, rapid index changes, removing the active item, network status |
| `advanced_test.dart` | Disk cache with offline replay, cache bypass, retry against a flaky local server, fullscreen orientation restoration |
| `benchmark_test.dart` | The benchmark, with behavioral assertions |

```bash
flutter test integration_test -d <device-id>
```

Every file attaches its per-test results to the report data, and
`test_driver/integration_test.dart` fails a `flutter drive` run in which
no test ran (for example when `setUpAll` threw), which the web runner
otherwise reports as passing.

### On the web

`flutter test` does not run integration tests in a browser; use
`flutter drive` with a chromedriver whose major version matches the
browser, one test file at a time:

```bash
chromedriver --port=4444 &
flutter drive -d web-server --browser-name=chrome --headless \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/playback_test.dart
# Add --chrome-binary=<path> for a Chromium-based browser other than Chrome.
```

Web-only tests check that autoplay with sound is refused with
`playbackNotAllowed` and fullscreen outside a user gesture with
`notAllowed` (or works, where the browser allows it). Tests needing the
local `dart:io` media server or device rotation are skipped.
