package dev.playstack.android

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterAssets
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Reads still frames for the scrub preview. Keeps the last few retrievers
 * open: opening one over the network is the slow part.
 */
internal class FrameExtractor(
    private val context: Context,
    private val flutterAssets: FlutterAssets,
) {
  private val retrievers = LinkedHashMap<String, MediaMetadataRetriever>()
  private val lock = Mutex()

  suspend fun frame(source: PlatformSource, positionMs: Long, maxWidth: Long): ByteArray? =
      withContext(Dispatchers.IO) {
        lock.withLock {
          try {
            val retriever = retriever(source) ?: return@withLock null
            val bitmap = read(retriever, positionMs * 1000, maxWidth.toInt()) ?: return@withLock null
            ByteArrayOutputStream().use { out ->
              bitmap.compress(Bitmap.CompressFormat.JPEG, 70, out)
              bitmap.recycle()
              out.toByteArray()
            }
          } catch (error: Exception) {
            null
          }
        }
      }

  private fun read(retriever: MediaMetadataRetriever, timeUs: Long, maxWidth: Int): Bitmap? {
    val option = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      val width =
          retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
      val height =
          retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
      if (width != null && height != null && width > 0 && height > 0) {
        val rotation =
            retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
        val (w, h) = if (rotation % 180 == 0) width to height else height to width
        val scale = minOf(1.0, maxWidth.toDouble() / w)
        return retriever.getScaledFrameAtTime(
            timeUs, option, (w * scale).toInt().coerceAtLeast(1), (h * scale).toInt().coerceAtLeast(1))
      }
    }
    val frame = retriever.getFrameAtTime(timeUs, option) ?: return null
    if (frame.width <= maxWidth) return frame
    val scaled =
        Bitmap.createScaledBitmap(frame, maxWidth, frame.height * maxWidth / frame.width, true)
    frame.recycle()
    return scaled
  }

  private fun retriever(source: PlatformSource): MediaMetadataRetriever? {
    if (source.drm != null) return null
    if (source.formatHint == PlatformVideoFormat.HLS ||
        source.formatHint == PlatformVideoFormat.DASH) {
      return null
    }
    val key =
        when (source.type) {
          PlatformSourceType.NETWORK,
          PlatformSourceType.FILE -> source.uri ?: return null
          PlatformSourceType.ASSET -> "asset:${source.assetPackage}/${source.assetName}"
          PlatformSourceType.MEMORY -> return null
        }
    retrievers.remove(key)?.let {
      retrievers[key] = it
      return it
    }
    val retriever = MediaMetadataRetriever()
    try {
      when (source.type) {
        PlatformSourceType.NETWORK -> {
          val uri = source.uri!!
          val lower = uri.substringBefore('?').lowercase()
          if (lower.endsWith(".m3u8") || lower.endsWith(".mpd")) return null
          retriever.setDataSource(uri, source.httpHeaders)
        }
        PlatformSourceType.FILE -> retriever.setDataSource(source.uri!!.removePrefix("file://"))
        PlatformSourceType.ASSET -> {
          val name = source.assetName ?: return null
          val path =
              source.assetPackage?.let { flutterAssets.getAssetFilePathByName(name, it) }
                  ?: flutterAssets.getAssetFilePathByName(name)
          context.assets.openFd(path).use {
            retriever.setDataSource(it.fileDescriptor, it.startOffset, it.length)
          }
        }
        PlatformSourceType.MEMORY -> return null
      }
    } catch (error: Exception) {
      retriever.release()
      return null
    }
    retrievers[key] = retriever
    while (retrievers.size > 3) {
      val oldest = retrievers.keys.first()
      retrievers.remove(oldest)?.release()
    }
    return retriever
  }

  fun release() {
    retrievers.values.forEach { it.release() }
    retrievers.clear()
  }

}
