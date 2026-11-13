package dev.playstack.android

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Timeline
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.TrackGroupArray
import androidx.media3.exoplayer.trackselection.ExoTrackSelection
import androidx.media3.exoplayer.upstream.Allocator

/**
 * [DefaultLoadControl] with an optional forward-buffer cap that applies only
 * while playback is not requested.
 *
 * Players prepared ahead of time (feed preloading) would otherwise keep
 * downloading up to the default 50 s buffer for a video the user may never
 * watch. Once the user plays, `playWhenReady` is true and the default policy
 * applies again without any extra call.
 */
@OptIn(UnstableApi::class)
internal class PreloadLoadControl(
    private val delegate: DefaultLoadControl = DefaultLoadControl.Builder().build(),
) : LoadControl {
  /** Forward buffer limit in microseconds while paused, or [C.TIME_UNSET]. */
  @Volatile var pausedBufferLimitUs: Long = C.TIME_UNSET

  override fun shouldContinueLoading(parameters: LoadControl.Parameters): Boolean {
    val limit = pausedBufferLimitUs
    if (limit != C.TIME_UNSET &&
        !parameters.playWhenReady &&
        parameters.bufferedDurationUs >= limit) {
      return false
    }
    return delegate.shouldContinueLoading(parameters)
  }

  override fun onPrepared(playerId: PlayerId) = delegate.onPrepared(playerId)

  override fun onTracksSelected(
      parameters: LoadControl.Parameters,
      trackGroups: TrackGroupArray,
      trackSelections: Array<out ExoTrackSelection?>,
  ) = delegate.onTracksSelected(parameters, trackGroups, trackSelections)

  override fun onTracksSelected(
      playerId: PlayerId,
      timeline: Timeline,
      mediaPeriodId: MediaSource.MediaPeriodId,
      renderers: Array<out Renderer>,
      trackGroups: TrackGroupArray,
      trackSelections: Array<out ExoTrackSelection?>,
  ) = delegate.onTracksSelected(playerId, timeline, mediaPeriodId, renderers, trackGroups, trackSelections)

  override fun onStopped(playerId: PlayerId) = delegate.onStopped(playerId)

  override fun onReleased(playerId: PlayerId) = delegate.onReleased(playerId)

  override fun getAllocator(playerId: PlayerId): Allocator = delegate.getAllocator(playerId)

  override fun getBackBufferDurationUs(playerId: PlayerId): Long =
      delegate.getBackBufferDurationUs(playerId)

  override fun retainBackBufferFromKeyframe(playerId: PlayerId): Boolean =
      delegate.retainBackBufferFromKeyframe(playerId)

  override fun shouldContinuePreloading(
      playerId: PlayerId,
      timeline: Timeline,
      mediaPeriodId: MediaSource.MediaPeriodId,
      bufferedDurationUs: Long,
  ): Boolean = delegate.shouldContinuePreloading(playerId, timeline, mediaPeriodId, bufferedDurationUs)

  override fun shouldStartPlayback(parameters: LoadControl.Parameters): Boolean =
      delegate.shouldStartPlayback(parameters)
}
