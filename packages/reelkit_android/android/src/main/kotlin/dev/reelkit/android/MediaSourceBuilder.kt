package dev.reelkit.android

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.datasource.ByteArrayDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterAssets
import java.io.File

/** Turns a [PlatformSource] into a Media3 [MediaSource]. */
@OptIn(UnstableApi::class)
internal class MediaSourceBuilder(
    private val context: Context,
    private val flutterAssets: FlutterAssets,
    private val engineConfig: () -> PlatformEngineConfig?,
) {
  private val userAgent = Util.getUserAgent(context, "ReelKit")

  fun build(source: PlatformSource): MediaSource =
      when (source.type) {
        PlatformSourceType.NETWORK -> network(source)
        PlatformSourceType.FILE -> file(source)
        PlatformSourceType.ASSET -> asset(source)
        PlatformSourceType.MEMORY -> memory(source)
      }

  private fun network(source: PlatformSource): MediaSource {
    val uri = source.uri ?: throw invalid("A network source needs a URL.")
    val http =
        DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(source.httpHeaders)
    val item =
        MediaItem.Builder()
            .setUri(uri)
            .setMimeType(mimeType(source))
            .setCustomCacheKey(source.cacheKey)
            .build()
    val direct = DefaultDataSource.Factory(context, http)
    return DefaultMediaSourceFactory(cachingFactory(source, direct) ?: direct)
        .createMediaSource(item)
  }

  /** A data source factory that uses the disk cache, or null when off. */
  private fun cachingFactory(
      source: PlatformSource,
      direct: DataSource.Factory,
  ): DataSource.Factory? {
    val config = engineConfig() ?: return null
    if (!config.cacheEnabled || !source.useCache || config.cacheMaxBytes <= 0) return null
    val cache = MediaCache.obtain(context, config.cacheMaxBytes)
    val cached =
        CacheDataSource.Factory()
            .setCache(cache)
            .setUpstreamDataSourceFactory(direct)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
    return ManifestBypassDataSource.Factory(cached, direct)
  }

  private fun file(source: PlatformSource): MediaSource {
    val path = source.uri ?: throw invalid("A file source needs a path.")
    val file = File(path)
    if (!file.isFile) {
      throw FlutterError("sourceNotFound", "File not found: $path", null)
    }
    return local(Uri.fromFile(file), source)
  }

  private fun asset(source: PlatformSource): MediaSource {
    val name = source.assetName ?: throw invalid("An asset source needs an asset name.")
    val key =
        source.assetPackage?.let { flutterAssets.getAssetFilePathByName(name, it) }
            ?: flutterAssets.getAssetFilePathByName(name)
    return local(Uri.parse("asset:///$key"), source)
  }

  private fun memory(source: PlatformSource): MediaSource {
    val bytes = source.bytes ?: throw invalid("A memory source needs bytes.")
    val item =
        MediaItem.Builder()
            .setUri(Uri.parse("reelkit-memory://${System.identityHashCode(bytes)}"))
            .setMimeType(source.mimeType)
            .build()
    val factory = DataSource.Factory { ByteArrayDataSource(bytes) }
    return ProgressiveMediaSource.Factory(factory).createMediaSource(item)
  }

  private fun local(uri: Uri, source: PlatformSource): MediaSource {
    val item = MediaItem.Builder().setUri(uri).setMimeType(mimeType(source)).build()
    return DefaultMediaSourceFactory(DefaultDataSource.Factory(context)).createMediaSource(item)
  }

  private fun mimeType(source: PlatformSource): String? =
      when (source.formatHint) {
        PlatformVideoFormat.HLS -> MimeTypes.APPLICATION_M3U8
        PlatformVideoFormat.DASH -> MimeTypes.APPLICATION_MPD
        PlatformVideoFormat.AUTO,
        PlatformVideoFormat.PROGRESSIVE -> source.mimeType
      }

  private fun invalid(message: String) = FlutterError("invalidSource", message, null)
}
