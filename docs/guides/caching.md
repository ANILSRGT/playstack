# Caching

Watched and preloaded video is kept on disk, so scrolling back, replaying
and playing a preloaded item do not download the same bytes again.

```dart
final manager = PlayStackManager(
  config: const PlayStackConfig(
    cache: PlayStackCacheConfig(maxBytes: 512 * 1024 * 1024), // default 256 MB
    // cache: PlayStackCacheConfig.disabled,
  ),
);
```

The cache is shared by every manager of the app and sized by the first
manager that initializes the engine. Least recently used videos are
evicted beyond `maxBytes`; videos being played are never evicted.

## What is cached

| Platform | Cached | Not cached |
| --- | --- | --- |
| Android | Progressive files and HLS/DASH segments (Media3 `SimpleCache`) | Manifests (`.m3u8`, `.mpd`), always fetched fresh so live and updated playlists work |
| iOS | Progressive files (MP4, MOV), including partial downloads and seeks | HLS: AVFoundation does not allow a custom loader for HLS segments |
| Web | Nothing by PlayStack | The browser's HTTP cache applies on its own terms |

Asset, file and memory sources never use the cache.

## Per source

```dart
// Signed URLs change on every request: give them a stable key.
PlayStackSource.network(signedUrl, cacheKey: 'video-${post.id}');

// Private or one-time content stays off disk.
PlayStackSource.network(url, cachePolicy: PlayStackCachePolicy.bypass);
```

## Inspecting and clearing

```dart
final cache = manager.cache;
if (cache.isSupported) {
  final info = await cache.info();
  print('${info.usedBytes ~/ (1 << 20)} of ${info.maxBytes ~/ (1 << 20)} MB');
  await cache.remove(source as PlayStackNetworkSource); // content changed under the same URL
  final bytes = await cache.cachedBytes(source as PlayStackNetworkSource);
  await cache.clear();                             // e.g. from a settings screen
}
```

`remove` and `cachedBytes` act on progressive files; HLS and DASH segments
are cached under their own URLs and are only removed by `clear` or
eviction.

## How it works

- **Android:** a process-wide `SimpleCache` with an LRU evictor in the
  app's cache directory, wrapped around the HTTP data source. Requests for
  manifests bypass it.
- **iOS:** progressive URLs are rewritten to a private scheme so
  `AVAssetResourceLoader` asks PlayStack for bytes. Ranges already on disk are
  answered from a sparse file; the rest is downloaded with range requests,
  passed to AVFoundation and written to disk. An index records which byte
  ranges of each file are valid, so partially watched videos are cached as
  far as they were downloaded.
