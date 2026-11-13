import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// Inspects and clears the engine's disk cache of network videos.
///
/// Android caches progressive files and HLS/DASH segments (manifests are
/// always fetched fresh). iOS caches progressive files (MP4/MOV); HLS is not
/// cached on iOS. Browsers manage their own HTTP cache, which PlayStack can
/// neither size, inspect nor clear: on web [info] reports a disabled cache
/// and the other methods have nothing to act on.
///
/// The cache is shared by every manager of the app; the first manager's
/// `PlayStackCacheConfig` sizes it.
class PlayStackCacheManager {
  /// Creates a cache manager. Applications use `PlayStackManager.cache`
  /// instead of constructing one.
  PlayStackCacheManager(this._platform, this._capabilities);

  final PlayStackPlatform _platform;
  final PlayStackPlatformCapabilities _capabilities;

  /// Whether this engine has a PlayStack-managed disk cache.
  bool get isSupported => _capabilities.supportsDiskCache;

  /// Current size and limit.
  Future<PlayStackCacheInfo> info() async {
    if (!isSupported) return PlayStackCacheInfo.disabled;
    return _platform.getCacheInfo();
  }

  /// Deletes every cached video that is not being read right now.
  Future<void> clear() async {
    if (!isSupported) return;
    await _platform.clearCache();
  }

  /// Deletes the cached data of [source] (by its cache key), for example
  /// when its content changed under the same URL. For HLS and DASH this
  /// removes nothing: segments are cached under their own URLs.
  Future<void> remove(PlayStackNetworkSource source) async {
    if (!isSupported) return;
    await _platform.removeCached(source.effectiveCacheKey);
  }

  /// Bytes of [source] available in the cache (0 when nothing is cached or
  /// the engine has no cache).
  Future<int> cachedBytes(PlayStackNetworkSource source) async {
    if (!isSupported) return 0;
    return _platform.getCachedBytes(source.effectiveCacheKey);
  }
}
