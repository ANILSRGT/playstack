package dev.playstack.android

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer

/**
 * Lists and selects audio, video and text tracks of one [ExoPlayer].
 *
 * Track ids are `"<groupIndex>:<trackIndex>"` within `currentTracks`, which
 * is stable for one source.
 */
@OptIn(UnstableApi::class)
internal class TrackSelection(private val player: ExoPlayer) {
  private val defaults: TrackSelectionParameters = player.trackSelectionParameters

  /**
   * Restores the player's original selection parameters for a new source.
   * The video quality limit is not part of them (see [VideoQualityLimit]).
   */
  fun reset() {
    player.trackSelectionParameters = defaults
  }

  fun list(): List<PlatformTrack> {
    val result = ArrayList<PlatformTrack>()
    player.currentTracks.groups.forEachIndexed { groupIndex, group ->
      val type = platformType(group.type) ?: return@forEachIndexed
      for (trackIndex in 0 until group.length) {
        if (!group.isTrackSupported(trackIndex)) continue
        val format = group.getTrackFormat(trackIndex)
        result.add(
            PlatformTrack(
                id = "$groupIndex:$trackIndex",
                type = type,
                isSelected = group.isTrackSelected(trackIndex),
                label = format.label,
                language = format.language,
                bitrate = known(format.bitrate)?.toLong(),
                width = known(format.width)?.toLong(),
                height = known(format.height)?.toLong(),
                frameRate = format.frameRate.takeIf { it > 0 }?.toDouble(),
                codecs = format.codecs ?: format.sampleMimeType,
                channelCount = known(format.channelCount)?.toLong(),
            ))
      }
    }
    return result
  }

  fun select(type: PlatformTrackType, trackId: String?) {
    val trackType = mediaType(type)
    val builder = player.trackSelectionParameters.buildUpon()
    if (trackId == null) {
      builder.clearOverridesOfType(trackType)
      builder.setTrackTypeDisabled(trackType, type == PlatformTrackType.TEXT)
    } else {
      val parts = trackId.split(":")
      val groupIndex = parts.getOrNull(0)?.toIntOrNull()
      val trackIndex = parts.getOrNull(1)?.toIntOrNull()
      val group = groupIndex?.let { player.currentTracks.groups.getOrNull(it) }
      if (group == null || trackIndex == null || trackIndex !in 0 until group.length ||
          group.type != trackType) {
        throw FlutterError("invalidArgument", "Unknown ${type.name.lowercase()} track: $trackId", null)
      }
      builder
          .setTrackTypeDisabled(trackType, false)
          .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, trackIndex))
    }
    player.trackSelectionParameters = builder.build()
  }

  private fun platformType(type: Int): PlatformTrackType? =
      when (type) {
        C.TRACK_TYPE_AUDIO -> PlatformTrackType.AUDIO
        C.TRACK_TYPE_VIDEO -> PlatformTrackType.VIDEO
        C.TRACK_TYPE_TEXT -> PlatformTrackType.TEXT
        else -> null
      }

  private fun mediaType(type: PlatformTrackType): Int =
      when (type) {
        PlatformTrackType.AUDIO -> C.TRACK_TYPE_AUDIO
        PlatformTrackType.VIDEO -> C.TRACK_TYPE_VIDEO
        PlatformTrackType.TEXT -> C.TRACK_TYPE_TEXT
      }

  private fun known(value: Int): Int? = value.takeIf { it != Format.NO_VALUE && it > 0 }
}
