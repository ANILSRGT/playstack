# Protected content (DRM)

Pass a `PlayStackDrm` to a network source:

```dart
// Android: DASH or HLS with Widevine
PlayStackSource.network(
  'https://cdn.example.com/movie.mpd',
  drm: PlayStackDrm.widevine(
    licenseUrl: 'https://license.example.com/widevine',
    headers: {'Authorization': 'Bearer $token'},
  ),
);

// iOS: HLS with FairPlay
PlayStackSource.network(
  'https://cdn.example.com/movie.m3u8',
  drm: PlayStackDrm.fairPlay(
    certificateUrl: 'https://license.example.com/fairplay.cer',
    licenseUrl: 'https://license.example.com/fairplay',
  ),
);
```

Use one source per platform when your streams differ:

```dart
final source = Platform.isIOS ? fairPlaySource : widevineSource;
```

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Widevine | Yes | No | No |
| PlayReady | Devices that support it | No | No |
| ClearKey (testing) | Yes | No | No |
| FairPlay | No | Yes (HLS) | No |

## License requests

The license request body is the raw challenge (the SPC for FairPlay) and
the response the raw license (the CKC), the format most license servers
(DRMtoday, EZDRM, BuyDRM, Axinom, PallyCon, AWS Elemental) accept.
`headers` are sent with license and certificate requests; put tokens
there. For FairPlay, `contentId` is the asset id sent to the key server;
null uses the host of the stream's `skd://` key URL.

A stream whose keys fail reports `PlayStackErrorCode.drm`.

## Rendering

Protected frames cannot be copied into a Flutter texture, so protected
videos are drawn through a platform view (a secure `SurfaceView` on
Android, an `AVPlayerLayer` on iOS). `PlayStackVideoView` picks this for
you. Platform views cost a little more than textures; keep only the
visible protected video in a view.

Screenshots and screen recordings of protected videos show black, as the
license requires.

## Testing

DRM needs a real device: simulators and emulators without Widevine L1
or FairPlay hardware may refuse keys. Your DRM provider usually offers a
test stream and license URL.
