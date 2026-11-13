package dev.playstack.android

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener

/**
 * Reads HLS and DASH manifests from the network and everything else (media
 * segments, progressive files) through the cache.
 *
 * Manifests of live streams change under the same URL; serving them from
 * the cache would freeze the stream. Segment URLs are immutable, so caching
 * them is safe for live and on-demand content alike.
 */
@OptIn(UnstableApi::class)
internal class ManifestBypassDataSource(
    private val cached: DataSource,
    private val direct: DataSource,
) : DataSource {
  private var current: DataSource? = null

  override fun addTransferListener(transferListener: TransferListener) {
    cached.addTransferListener(transferListener)
    direct.addTransferListener(transferListener)
  }

  override fun open(dataSpec: DataSpec): Long {
    val source = if (isManifest(dataSpec.uri)) direct else cached
    current = source
    return source.open(dataSpec)
  }

  override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
      checkNotNull(current) { "read() before open()" }.read(buffer, offset, length)

  override fun getUri(): Uri? = current?.uri

  override fun getResponseHeaders(): Map<String, List<String>> =
      current?.responseHeaders ?: emptyMap()

  override fun close() {
    try {
      current?.close()
    } finally {
      current = null
    }
  }

  class Factory(
      private val cached: DataSource.Factory,
      private val direct: DataSource.Factory,
  ) : DataSource.Factory {
    override fun createDataSource(): DataSource =
        ManifestBypassDataSource(cached.createDataSource(), direct.createDataSource())
  }

  companion object {
    fun isManifest(uri: Uri): Boolean {
      val path = uri.path?.lowercase() ?: return false
      return path.endsWith(".m3u8") || path.endsWith(".m3u") || path.endsWith(".mpd")
    }
  }
}
