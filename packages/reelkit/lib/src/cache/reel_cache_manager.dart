import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// Inspects and clears the engine's disk cache of network videos.
///
/// Android caches progressive files and HLS/DASH segments (manifests are
/// always fetched fresh). iOS caches progressive files (MP4/MOV); HLS is not
/// cached on iOS. Browsers manage their own HTTP cache, which ReelKit can
/// neither size, inspect nor clear: on web [info] reports a disabled cache
/// and the other methods have nothing to act on.
///
/// The cache is shared by every manager of the app; the first manager's
/// `ReelCacheConfig` sizes it.
class ReelCacheManager {
  /// Creates a cache manager. Applications use `ReelKitManager.cache`
  /// instead of constructing one.
  ReelCacheManager(this._platform, this._capabilities);

  final ReelKitPlatform _platform;
  final ReelPlatformCapabilities _capabilities;

  /// Whether this engine has a ReelKit-managed disk cache.
  bool get isSupported => _capabilities.supportsDiskCache;

  /// Current size and limit.
  Future<ReelCacheInfo> info() async {
    if (!isSupported) return ReelCacheInfo.disabled;
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
  Future<void> remove(ReelNetworkSource source) async {
    if (!isSupported) return;
    await _platform.removeCached(source.effectiveCacheKey);
  }

  /// Bytes of [source] available in the cache (0 when nothing is cached or
  /// the engine has no cache).
  Future<int> cachedBytes(ReelNetworkSource source) async {
    if (!isSupported) return 0;
    return _platform.getCachedBytes(source.effectiveCacheKey);
  }
}
