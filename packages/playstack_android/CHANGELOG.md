## 0.2.0

* Released with playstack 0.2.0 to keep every package on the same
  version. No changes in this package.

## 0.1.0+1

* Released with playstack 0.1.0+1 to keep every package on the same
  version. No code changes.

## 0.1.0

* First stable release. The integration suite and the benchmark pass on a
  physical Android phone (Android 16) and an iPhone (iOS 26.6.1).

## 0.1.0-dev.10

* DRM: Widevine, PlayReady and ClearKey through Media3's
  `DrmConfiguration`; protected players render into a secure
  `SurfaceView` platform view (`dev.playstack/secure_video`). Errors
  6000 to 6999 report `drm`.
* `setVideoDisabled` (audio only) disables the video track type.
* Live streams: window start and live edge in positions,
  `seekToLiveEdge`.
* `getFrame` reads frames with `MediaMetadataRetriever` for the scrub
  preview; the last three videos stay open.
* Screen brightness through the window's `screenBrightness`.

* Offline downloads with a Media3 `DownloadManager` in a separate,
  never-evicted cache: progressive files, and HLS and DASH up to a maximum
  height. Downloaded sources play from that cache while downloads are
  enabled. `PlayStackDownloadService` (declared by the app) keeps them
  running in the background with a progress notification. HLS and DASH
  downloads keep the source's cache key in their data (Media3 does not
  allow one on adaptive requests).

## 0.1.0-dev.8

* Media controls through a Media3 `MediaSession` whose commands go to Dart;
  `PlayStackMediaService` (declared by the app) shows the notification and
  keeps playback alive in the background.
* Picture-in-Picture of the activity with the video's aspect ratio,
  automatic on leaving the app (`setAutoEnterEnabled` on Android 12+, the
  user-leave hint before).
* Device orientation from `OrientationEventListener`, also while the
  activity is locked to one orientation, and the app's requested
  orientation for restoring it after fullscreen.

## 0.1.0-dev.7

* Licensed under the MIT license.
* Package metadata and aligned dependency constraints for publishing.

## 0.1.0-dev.6

* Milestone 6: Media3 `SimpleCache` with manifest bypass, audio focus only
  while audible, pause on headphones unplugged, interruption events,
  SystemChrome fullscreen.

## 0.1.0-dev.5

* Milestone 5: preload buffer cap through a wrapping `LoadControl`; network
  status from `ConnectivityManager` (adds `ACCESS_NETWORK_STATE`).

## 0.1.0-dev.4

* Milestone 4: `ERROR_CODE_DECODER_INIT_FAILED` is reported as
  `decoderUnavailable`.

## 0.1.0-dev.3

* Milestone 3: audio/video/subtitle tracks with subtitle text events, video
  quality limits, metadata (frame rate, bitrate, codec, live), `setSource`,
  `stop`, `positions()` stream, app lifecycle pause/resume.

## 0.1.0-dev.2

* Milestone 2: native playback (sources, play/pause/seek/loop, volume, speed,
  first frame, rotation, typed errors), `clearSource` for idle pooled players.

## 0.1.0-dev.1

* Milestone 1 foundation. Development preview; see the repository README for status.
