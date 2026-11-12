# ReelKit demo

A small short-video app built on ReelKit. The feed is ReelKit's
`ReelFeedView`. The demo adds only its own overlay (`lib/reel_overlay.dart`)
on top of `ReelDefaultControls`: a caption and like (also on double tap).
Sound, fullscreen for landscape videos, progress and retry come from the
default controls. The tune button switches the transition (slide,
parallax, stack, fade, zoom, cube), the swipe direction and reverse. The
stats button opens a live sheet with pool, preloading, start latency,
network and disk cache figures.

```bash
cd demo
flutter run                 # Android or iOS device/simulator
flutter run -d chrome       # web (starts muted: browsers block autoplay with sound)
```
