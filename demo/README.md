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

Media are public test videos (MDN CC0 clips, test-videos.co.uk, Mux and
Apple HLS test streams, samplelib) plus one bundled vertical test card, so
an internet connection is needed.
