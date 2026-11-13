## Unreleased

* `deviceOrientationChanges` (how the user holds the device, from the
  motion sensors) and `getAppOrientations` (the orientations the app allows
  right now).

## 0.1.0-dev.7

* Licensed under the MIT license.
* Every public member is documented (`public_member_api_docs`).
* Package metadata for publishing.

## 0.1.0-dev.6

* Milestone 6: `PlayStackEngineConfig` passed to `initialize`, cache methods,
  `PlayStackCachePolicy`, fullscreen methods with the `SystemChromeFullscreen`
  mixin, `PlayStackInterruptionEvent`, `PlayStackErrorCode.notAllowed`.

## 0.1.0-dev.5

* Milestone 5: `setPreloadBufferLimit`, `getNetworkStatus`,
  `networkStatusChanges`, `PlayStackNetworkStatus`, capability flags
  `supportsPreloadBufferLimit` and `supportsNetworkStatus`.

## 0.1.0-dev.4

* Milestone 4: `PlayStackErrorCode.decoderUnavailable` for decoders that exist
  but cannot be allocated.

## 0.1.0-dev.3

* Milestone 3: audio/video/subtitle tracks with subtitle text events, video
  quality limits, metadata (frame rate, bitrate, codec, live), `setSource`,
  `stop`, `positions()` stream, app lifecycle pause/resume.

## 0.1.0-dev.2

* Milestone 2: native playback (sources, play/pause/seek/loop, volume, speed,
  first frame, rotation, typed errors), `clearSource` for idle pooled players.

## 0.1.0-dev.1

* Milestone 1 foundation. Development preview; see the repository README for status.
