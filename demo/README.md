# ReelKit demo

A small short-video app built on ReelKit: an endless vertical feed with
preloading, tap to pause, double-tap to like, sound toggle, fit/fill for
landscape videos, fullscreen with orientation lock, an error panel with
retry, and a live stats sheet (pool, preloading, start latency, network,
disk cache).

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
