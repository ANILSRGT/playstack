package dev.reelkit.android

import androidx.annotation.OptIn
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.util.Clock
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.upstream.BandwidthMeter
import com.google.common.collect.ImmutableList

/**
 * A player's video quality limit, applied inside adaptive track selection.
 *
 * Changing `TrackSelectionParameters` invalidates the current selection:
 * HLS and DASH then discard the buffer and load again, so playback stops.
 * A limit read by [LimitedAdaptiveTrackSelection] instead takes effect at
 * the next chunk the player loads, like any adaptive switch: lifting it
 * switches up once enough is buffered, without a stall.
 *
 * Written on the main thread, read on the playback thread.
 */
internal class VideoQualityLimit {
  @Volatile var maxBitrate: Int = Int.MAX_VALUE
  @Volatile var maxWidth: Int = Int.MAX_VALUE
  @Volatile var maxHeight: Int = Int.MAX_VALUE

  fun set(bitrate: Long?, width: Long?, height: Long?) {
    maxBitrate = bitrate?.toIntCapped() ?: Int.MAX_VALUE
    maxWidth = width?.toIntCapped() ?: Int.MAX_VALUE
    maxHeight = height?.toIntCapped() ?: Int.MAX_VALUE
  }

  /** Whether [format], a video rendition of [bitrate], is within the limit. */
  fun allows(format: Format, bitrate: Int): Boolean {
    if (!isVideo(format)) return true
    if (bitrate != Format.NO_VALUE && bitrate > maxBitrate) return false
    if (format.width != Format.NO_VALUE && format.width > maxWidth) return false
    if (format.height != Format.NO_VALUE && format.height > maxHeight) return false
    return true
  }

  private fun isVideo(format: Format): Boolean =
      format.width != Format.NO_VALUE ||
          format.height != Format.NO_VALUE ||
          MimeTypes.isVideo(format.sampleMimeType) ||
          MimeTypes.getVideoMediaMimeType(format.codecs) != null

  private fun Long.toIntCapped(): Int = coerceIn(0, Int.MAX_VALUE.toLong()).toInt()
}

/** Creates [LimitedAdaptiveTrackSelection]s that read [limit]. */
@OptIn(UnstableApi::class)
internal class LimitedAdaptiveTrackSelectionFactory(private val limit: VideoQualityLimit) :
    AdaptiveTrackSelection.Factory() {
  override fun createAdaptiveTrackSelection(
      group: TrackGroup,
      tracks: IntArray,
      type: Int,
      bandwidthMeter: BandwidthMeter,
      adaptationCheckpoints: ImmutableList<AdaptiveTrackSelection.AdaptationCheckpoint>,
  ): AdaptiveTrackSelection =
      LimitedAdaptiveTrackSelection(group, tracks, type, bandwidthMeter, adaptationCheckpoints, limit)
}

/**
 * [AdaptiveTrackSelection] that skips renditions over [limit].
 *
 * Switches up once [MIN_BUFFER_FOR_QUALITY_INCREASE_MS] is buffered instead
 * of Media3's 10 s: short videos would otherwise play most of their length
 * at the rendition they started with. A rendition is only chosen when the
 * measured bandwidth sustains it, and one segment of margin keeps the
 * switch from stalling.
 */
@OptIn(UnstableApi::class)
internal class LimitedAdaptiveTrackSelection(
    group: TrackGroup,
    tracks: IntArray,
    type: Int,
    bandwidthMeter: BandwidthMeter,
    adaptationCheckpoints: List<AdaptationCheckpoint>,
    private val limit: VideoQualityLimit,
) :
    AdaptiveTrackSelection(
        group,
        tracks,
        type,
        bandwidthMeter,
        MIN_BUFFER_FOR_QUALITY_INCREASE_MS,
        DEFAULT_MAX_DURATION_FOR_QUALITY_DECREASE_MS.toLong(),
        DEFAULT_MIN_DURATION_TO_RETAIN_AFTER_DISCARD_MS.toLong(),
        DEFAULT_MAX_WIDTH_TO_DISCARD,
        DEFAULT_MAX_HEIGHT_TO_DISCARD,
        DEFAULT_BANDWIDTH_FRACTION,
        DEFAULT_BUFFERED_FRACTION_TO_LIVE_EDGE_FOR_QUALITY_INCREASE,
        adaptationCheckpoints,
        Clock.DEFAULT,
    ) {
  companion object {
    const val MIN_BUFFER_FOR_QUALITY_INCREASE_MS = 4_000L
  }

  override fun canSelectFormat(format: Format, trackBitrate: Int, effectiveBitrate: Long): Boolean =
      limit.allows(format, trackBitrate) &&
          super.canSelectFormat(format, trackBitrate, effectiveBitrate)
}
