# Errors and retry

Every failure is a `ReelKitException` with a `ReelKitErrorCode`, a
`message` for logs and optional engine `details`.

```dart
try {
  await controller.play();
} on ReelKitException catch (error) {
  switch (error.code) {
    case ReelKitErrorCode.network:
    case ReelKitErrorCode.timeout:
      showRetry();
    case ReelKitErrorCode.sourceNotFound:
      removeItem();
    case ReelKitErrorCode.playbackNotAllowed:
      showTapToPlay();
    default:
      log(error.toString());
  }
}
```

Errors are also reflected in the state: `controller.value.hasError` and
`controller.value.error`, so a `ReelVideoView.errorBuilder` or a
`ValueListenableBuilder` can show them without a `try`.

## Codes

| Code | Meaning |
| --- | --- |
| `network` | Connection failed or the server answered with an error other than 404/410 |
| `timeout` | Preparation did not finish within `ReelPlayerConfig.initializeTimeout` (30 s) |
| `sourceNotFound` | HTTP 404/410, missing file or asset |
| `invalidSource` | Malformed source, or not usable on this platform (file or headers on web) |
| `unsupportedFormat` | Container or codec not supported (for example DASH on iOS) |
| `decoder` | Decoding failed, or no decoder exists for the media |
| `decoderUnavailable` | A decoder exists but every instance is in use; ReelKit shrinks the pool and retries once |
| `playbackNotAllowed` | The browser blocked autoplay with sound |
| `notAllowed` | A request needed a user gesture or permission (web fullscreen) |
| `poolExhausted` | Every native player is held by a controller of equal or higher priority |
| `cancelled` | Superseded, for example the controller lost its player or was released |
| `disposed`, `notInitialized` | The object was disposed, or the manager not initialized |
| `notImplemented`, `unsupportedPlatform` | Not available on this engine or platform |
| `invalidArgument`, `playerNotFound`, `playerCreationFailed`, `unknown` | Other failures |

## Automatic retry

`ReelRetryConfig` retries `network` and `timeout` failures:

- a failed preparation is retried inside the same `initialize` / `play`
  call, which completes only when it succeeds or retries run out;
- a failure during playback prepares the video again, seeks back to where
  it stopped and resumes if it was playing;
- controllers that failed offline retry when the network returns.

```dart
const ReelPlayerConfig(
  retry: ReelRetryConfig(
    maxAttempts: 3,                       // default 2
    initialDelay: Duration(milliseconds: 500),
    multiplier: 2,                        // 0.5 s, 1 s, 2 s
    maxDelay: Duration(seconds: 8),
  ),
  // retry: ReelRetryConfig.none,
);
```

Waiting retries are cancelled by `release`, `setSource` and `dispose`.

## Manual retry

```dart
await controller.retry();        // after an error: prepare, seek back, resume
await controller.reinitialize(); // start over from the beginning
```

## Errors outside a call

Failures during playback (a network drop mid-video) are not thrown; they
appear in `controller.value` and, after automatic retries, stay there until
`retry`, `reinitialize` or `setSource`. Errors in background work of the
manager (lifecycle, memory pressure) are reported through
`FlutterError.reportError` and never thrown into your code.
