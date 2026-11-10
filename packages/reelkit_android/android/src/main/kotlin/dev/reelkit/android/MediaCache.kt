package dev.reelkit.android

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

/**
 * Process-wide Media3 disk cache.
 *
 * [SimpleCache] locks its directory, so one instance must serve every Flutter
 * engine of the process. The first configuration wins; later engines share
 * it. Least recently used content is evicted beyond the size limit.
 */
@OptIn(UnstableApi::class)
internal object MediaCache {
  private const val DIRECTORY = "reelkit_media_cache"

  @Volatile private var cache: SimpleCache? = null
  @Volatile private var maxBytes: Long = 0

  /** The cache, created on first use with [requestedMaxBytes]. */
  fun obtain(context: Context, requestedMaxBytes: Long): SimpleCache =
      cache
          ?: synchronized(this) {
            cache
                ?: SimpleCache(
                        File(context.applicationContext.cacheDir, DIRECTORY),
                        LeastRecentlyUsedCacheEvictor(requestedMaxBytes),
                        StandaloneDatabaseProvider(context.applicationContext),
                    )
                    .also {
                      cache = it
                      maxBytes = requestedMaxBytes
                    }
          }

  /** The existing cache without creating one. */
  fun existing(): SimpleCache? = cache

  val configuredMaxBytes: Long
    get() = maxBytes

  fun usedBytes(): Long = cache?.cacheSpace ?: 0

  fun clear() {
    val current = cache ?: return
    for (key in current.keys.toList()) {
      try {
        current.removeResource(key)
      } catch (_: RuntimeException) {
        // A span may be locked by an active reader; it is evicted later.
      }
    }
  }

  fun remove(key: String) {
    cache?.removeResource(key)
  }

  fun cachedBytes(key: String): Long =
      cache?.getCachedSpans(key)?.filter { it.isCached }?.sumOf { it.length } ?: 0
}
