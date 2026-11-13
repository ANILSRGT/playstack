package dev.playstack.android

import android.app.ActivityManager
import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import androidx.annotation.OptIn
import androidx.media3.common.MediaLibraryInfo
import androidx.media3.common.util.UnstableApi

/**
 * Reads device facts that drive the adaptive player pool size.
 *
 * The recommendation is a conservative heuristic, not a guarantee: decoder
 * availability also depends on other apps and on the codec of each stream.
 * Applications can always override it with an explicit pool size.
 */
internal object DeviceCapabilities {
  private const val GIB = 1024L * 1024L * 1024L

  @OptIn(UnstableApi::class)
  fun read(context: Context): PlatformCapabilities {
    val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    val memoryInfo = ActivityManager.MemoryInfo().also { activityManager.getMemoryInfo(it) }
    val isLowRam = activityManager.isLowRamDevice
    val totalMemory = memoryInfo.totalMem
    val decoderInstances = maxHardwareAvcDecoderInstances()

    val memoryBased =
        when {
          isLowRam -> 1
          totalMemory < 3 * GIB -> 2
          totalMemory < 6 * GIB -> 3
          else -> 4
        }
    val recommended =
        if (decoderInstances != null && decoderInstances > 0) {
          minOf(memoryBased, decoderInstances)
        } else {
          memoryBased
        }

    return PlatformCapabilities(
        engineName = "AndroidX Media3 ExoPlayer",
        engineVersion = MediaLibraryInfo.VERSION,
        recommendedMaxPlayers = recommended.toLong(),
        maxHardwareDecoderInstances = decoderInstances?.toLong(),
        totalMemoryBytes = totalMemory,
        isLowRamDevice = isLowRam,
        supportsHls = true,
        supportsDash = true,
        supportsDiskCache = true,
        supportsMemorySource = true,
        supportsTrackSelection = true,
        supportsVideoTrackSelection = true,
        supportsVideoQualityLimit = true,
        supportsPreloadBufferLimit = true,
        supportsNetworkStatus = true,
    )
  }

  /** Highest `maxSupportedInstances` among hardware H.264 decoders, or null when unknown. */
  private fun maxHardwareAvcDecoderInstances(): Int? =
      try {
        MediaCodecList(MediaCodecList.REGULAR_CODECS)
            .codecInfos
            .asSequence()
            .filter { !it.isEncoder && isHardware(it) }
            .filter { info -> info.supportedTypes.any { it.equals("video/avc", ignoreCase = true) } }
            .map { it.getCapabilitiesForType("video/avc").maxSupportedInstances }
            .maxOrNull()
      } catch (_: RuntimeException) {
        null
      }

  private fun isHardware(info: MediaCodecInfo): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      return info.isHardwareAccelerated
    }
    val name = info.name.lowercase()
    return !name.startsWith("omx.google.") && !name.startsWith("c2.android.")
  }
}
