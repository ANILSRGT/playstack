## 0.1.0-dev.4

* Milestone 4: exclusive playback (`ReelKitConfig.exclusivePlayback`,
  `ReelKitManager.activeController`), pool limit lowered and preparation
  retried once when a decoder cannot be allocated
  (`ReelPoolConfig.adaptToDecoderFailures`), memory pressure releases
  `background` controllers, per-priority pool stats. Fixes a lease leak when
  a controller was disposed while its native player was being created.

## 0.1.0-dev.3

* Milestone 3: audio/video/subtitle tracks with subtitle text events, video
  quality limits, metadata (frame rate, bitrate, codec, live), `setSource`,
  `stop`, `positions()` stream, app lifecycle pause/resume.

## 0.1.0-dev.2

* Milestone 2: native playback (sources, play/pause/seek/loop, volume, speed,
  first frame, rotation, typed errors), `clearSource` for idle pooled players.

## 0.1.0-dev.1

* Milestone 1 foundation. Development preview; see the repository README for status.
