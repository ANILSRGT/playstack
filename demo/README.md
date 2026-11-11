# ReelKit demo

A small short-video app built on ReelKit. The feed is ReelKit's
`ReelFeedView`. The demo adds only its own overlay (`lib/reel_overlay.dart`)
on top of `ReelDefaultControls`: caption, like (also on double tap), a
feed-wide sound switch, fit/fill for landscape videos and fullscreen with
orientation lock. The tune button switches the transition (slide,
parallax, stack, fade, zoom, cube), the swipe direction and reverse. The
stats button opens a live sheet with pool, preloading, start latency,
network and disk cache figures.

```bash
cd demo
flutter run                 # Android or iOS device/simulator
flutter run -d chrome       # web (starts muted: browsers block autoplay with sound)
```

Every item is an HLS stream (43 different ones, repeated endlessly):
15 vertical 9:16 reels from Cloudinary's public demo account (adaptive up
to 1080p), plus landscape test streams from Apple, Mux, Shaka, Unified
Streaming, JW Player and AWS. An internet
connection is needed. Cloudinary creates a rendition on first request, so
the first play of a reel can be slower than later ones.

Public test streams come and go. Check that every stream still prepares on
a device before a demo:

```bash
flutter test integration_test/catalog_test.dart -d <device-id>
```

The settings in `lib/settings.dart` are tuned for swiping two or three
videos a second: five items prepared ahead, three at a time, each at up
to ~720p until it plays (then it switches up). Cloudinary and Mux items
show a poster while they prepare. Measure how many items are ready on
arrival at that speed:

```bash
flutter test integration_test/swipe_test.dart -d <device-id>
```

Renditions are also capped to the screen size (lifted in fullscreen), so
switching up never asks for more than the screen shows. Check that
playback never stops, at a normal pace and after bursts of swipes, and
when the loading spinner appears in the real UI:

```bash
flutter test integration_test/stall_test.dart -d <device-id>
```

```bash
flutter test integration_test/app_swipe_test.dart -d <device-id>
```

Hold each transition halfway through a swipe, vertically and
horizontally, for screenshots (it prints `HOLD <name>` while holding):

```bash
flutter test integration_test/transitions_test.dart -d <device-id>
```
