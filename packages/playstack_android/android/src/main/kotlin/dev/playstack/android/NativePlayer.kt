package dev.playstack.android

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import io.flutter.view.TextureRegistry

/**
 * One Media3 [ExoPlayer] bound to one Flutter [TextureRegistry.SurfaceProducer].
 *
 * Events are tagged with the generation of the current source. After
 * [clearSource] no events are emitted until the next [setSource].
 */
@OptIn(UnstableApi::class)
internal class NativePlayer(
    val id: Long,
    context: Context,
    private val surfaceProducer: TextureRegistry.SurfaceProducer,
    private val events: PlayerEventDispatcher,
    options: PlatformPlayerOptions,
    private val engineConfig: PlatformEngineConfig,
) : Player.Listener {
  private val loadControl = PreloadLoadControl()
  private val videoLimit = VideoQualityLimit()
  private val exoPlayer: ExoPlayer =
      ExoPlayer.Builder(context)
          .setLoadControl(loadControl)
          .setTrackSelector(
              DefaultTrackSelector(context, LimitedAdaptiveTrackSelectionFactory(videoLimit)))
          .setHandleAudioBecomingNoisy(engineConfig.pauseOnAudioRouteLoss)
          .build()

  /** Whether the player currently asks for audio focus (only when audible). */
  private var requestsAudioFocus: Boolean? = null
  private val tracks = TrackSelection(exoPlayer)
  private var released = false
  private var generation = NO_SOURCE
  private var initializedSent = false

  val textureId: Long
    get() = surfaceProducer.id()

  init {
    setLooping(options.looping)
    setVolume(options.volume)
    setPlaybackSpeed(options.playbackSpeed)
    exoPlayer.addListener(this)

    surfaceProducer.setCallback(
        object : TextureRegistry.SurfaceProducer.Callback {
          override fun onSurfaceAvailable() {
            if (!released) exoPlayer.setVideoSurface(surfaceProducer.surface)
          }

          override fun onSurfaceCleanup() {
            if (!released) exoPlayer.setVideoSurface(null)
          }
        })
    exoPlayer.setVideoSurface(surfaceProducer.surface)
  }

  fun setSource(mediaSource: MediaSource, generation: Long) {
    // Silence the previous source before the new generation starts.
    this.generation = NO_SOURCE
    exoPlayer.playWhenReady = false
    this.generation = generation
    initializedSent = false
    tracks.reset()
    exoPlayer.setMediaSource(mediaSource, /* resetPosition= */ true)
    exoPlayer.prepare()
  }

  fun clearSource() {
    generation = NO_SOURCE
    initializedSent = false
    exoPlayer.playWhenReady = false
    exoPlayer.stop()
    exoPlayer.clearMediaItems()
    tracks.reset()
  }

  fun tracks(): List<PlatformTrack> = tracks.list()

  fun selectTrack(type: PlatformTrackType, trackId: String?) = tracks.select(type, trackId)

  /**
   * A player setting kept across sources. Applied inside adaptive selection
   * ([VideoQualityLimit]), so changing it never interrupts playback.
   */
  fun setVideoQualityLimit(maxBitrate: Long?, maxWidth: Long?, maxHeight: Long?) =
      videoLimit.set(maxBitrate, maxWidth, maxHeight)

  /** Caps forward buffering while paused; null removes the cap. */
  fun setPreloadBufferLimit(maxBufferMs: Long?) {
    loadControl.pausedBufferLimitUs = maxBufferMs?.let { it * 1000 } ?: C.TIME_UNSET
  }

  fun play() = exoPlayer.play()

  fun pause() = exoPlayer.pause()

  fun seekTo(positionMs: Long) = exoPlayer.seekTo(positionMs)

  fun setLooping(looping: Boolean) {
    exoPlayer.repeatMode = if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
  }

  fun setVolume(volume: Double) {
    val clamped = volume.toFloat().coerceIn(0f, 1f)
    exoPlayer.volume = clamped
    // A muted player (muted autoplay in a feed) must not take audio focus
    // from music the user is listening to.
    val wantsFocus = engineConfig.handleAudioFocus && clamped > 0f
    if (wantsFocus != requestsAudioFocus) {
      requestsAudioFocus = wantsFocus
      exoPlayer.setAudioAttributes(MEDIA_AUDIO, wantsFocus)
    }
  }

  fun setPlaybackSpeed(speed: Double) {
    exoPlayer.playbackParameters = PlaybackParameters(speed.toFloat())
  }

  fun position(): PlatformPosition =
      PlatformPosition(
          positionMs = exoPlayer.currentPosition, bufferedMs = exoPlayer.bufferedPosition)

  fun release() {
    if (released) return
    released = true
    generation = NO_SOURCE
    exoPlayer.removeListener(this)
    surfaceProducer.setCallback(null)
    exoPlayer.setVideoSurface(null)
    exoPlayer.release()
    surfaceProducer.release()
  }

  // Player.Listener ----------------------------------------------------------

  override fun onPlaybackStateChanged(playbackState: Int) {
    if (generation == NO_SOURCE) return
    val state =
        when (playbackState) {
          Player.STATE_BUFFERING -> PlatformPlaybackState.BUFFERING
          Player.STATE_READY -> {
            if (!initializedSent) sendInitialized()
            PlatformPlaybackState.READY
          }
          Player.STATE_ENDED -> PlatformPlaybackState.ENDED
          else -> PlatformPlaybackState.IDLE
        }
    events.emit(PlatformStateEvent(playerId = id, generation = generation, state = state))
    if (playbackState == Player.STATE_ENDED) {
      // ExoPlayer keeps playWhenReady at the end. Clearing it reports the
      // stop and lets the next play() start a new playback request.
      exoPlayer.playWhenReady = false
    }
  }

  override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
    if (generation == NO_SOURCE) return
    events.emit(
        PlatformIsPlayingEvent(playerId = id, generation = generation, isPlaying = playWhenReady))
    if (playWhenReady) return
    when (reason) {
      Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS ->
          emitInterruption(PlatformInterruptionType.AUDIO_INTERRUPTION, ended = false)
      Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_BECOMING_NOISY ->
          emitInterruption(PlatformInterruptionType.AUDIO_ROUTE_LOST, ended = false)
    }
  }

  override fun onPlaybackSuppressionReasonChanged(playbackSuppressionReason: Int) {
    if (generation == NO_SOURCE) return
    // Transient focus loss (a notification sound, navigation prompt):
    // ExoPlayer pauses output and resumes by itself afterwards.
    val transient =
        playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS
    if (transient) {
      suppressedByFocus = true
      emitInterruption(PlatformInterruptionType.AUDIO_INTERRUPTION, ended = false)
    } else if (suppressedByFocus) {
      suppressedByFocus = false
      emitInterruption(PlatformInterruptionType.AUDIO_INTERRUPTION, ended = true)
    }
  }

  private var suppressedByFocus = false

  private fun emitInterruption(type: PlatformInterruptionType, ended: Boolean) {
    events.emit(
        PlatformInterruptionEvent(
            playerId = id, generation = generation, type = type, ended = ended))
  }

  override fun onVideoSizeChanged(videoSize: VideoSize) {
    if (generation == NO_SOURCE || !initializedSent) return
    val geometry = geometry()
    if (geometry.width <= 0 || geometry.height <= 0) return
    events.emit(
        PlatformVideoSizeEvent(
            playerId = id,
            generation = generation,
            width = geometry.width.toLong(),
            height = geometry.height.toLong(),
            rotationDegrees = geometry.rotationDegrees.toLong(),
            pixelAspectRatio = geometry.pixelAspectRatio,
        ))
  }

  override fun onTracksChanged(tracks: Tracks) {
    if (generation == NO_SOURCE || !initializedSent) return
    events.emit(PlatformTracksChangedEvent(playerId = id, generation = generation))
  }

  override fun onCues(cueGroup: CueGroup) {
    if (generation == NO_SOURCE) return
    val texts = cueGroup.cues.mapNotNull { cue -> cue.text?.toString()?.takeIf { it.isNotBlank() } }
    events.emit(PlatformCuesEvent(playerId = id, generation = generation, texts = texts))
  }

  override fun onRenderedFirstFrame() {
    if (generation == NO_SOURCE) return
    events.emit(PlatformFirstFrameEvent(playerId = id, generation = generation))
  }

  override fun onPlayerError(error: PlaybackException) {
    if (generation == NO_SOURCE) return
    events.emit(
        PlatformErrorEvent(
            playerId = id,
            generation = generation,
            code = PlaybackErrors.code(error),
            message = error.message ?: error.errorCodeName,
            details = error.errorCodeName,
        ))
  }

  private fun sendInitialized() {
    initializedSent = true
    val geometry = geometry()
    val duration = exoPlayer.duration
    val format = exoPlayer.videoFormat
    events.emit(
        PlatformInitializedEvent(
            playerId = id,
            generation = generation,
            durationMs = if (duration == C.TIME_UNSET) -1 else duration,
            width = geometry.width.toLong(),
            height = geometry.height.toLong(),
            rotationDegrees = geometry.rotationDegrees.toLong(),
            pixelAspectRatio = geometry.pixelAspectRatio,
            isLive = exoPlayer.isCurrentMediaItemLive,
            frameRate = format?.frameRate?.takeIf { it > 0 }?.toDouble(),
            bitrate = format?.bitrate?.takeIf { it > 0 }?.toLong(),
            videoCodec = format?.codecs ?: format?.sampleMimeType,
        ))
  }

  /**
   * Size of the frames as they arrive in the Flutter texture, plus the
   * rotation Flutter still has to apply.
   *
   * Media3 reports [VideoSize] upright, assuming the surface honours the
   * decoder's rotation transform. The SurfaceTexture backend does; the
   * ImageReader backend (`handlesCropAndRotation() == false`) does not, so
   * its frames arrive unrotated and the rotation is reported to Flutter.
   */
  private fun geometry(): Geometry {
    val format = exoPlayer.videoFormat
    val rotation = ((format?.rotationDegrees ?: 0) % 360 + 360) % 360
    val quarterTurn = rotation == 90 || rotation == 270
    val handlesRotation = surfaceProducer.handlesCropAndRotation()
    val size = exoPlayer.videoSize
    if (size.width > 0 && size.height > 0) {
      val ratio = size.pixelWidthHeightRatio.toDouble()
      return when {
        handlesRotation -> Geometry(size.width, size.height, 0, ratio)
        quarterTurn -> Geometry(size.height, size.width, rotation, 1.0 / ratio)
        else -> Geometry(size.width, size.height, rotation, ratio)
      }
    }
    if (format != null && format.width > 0 && format.height > 0) {
      val ratio = format.pixelWidthHeightRatio.toDouble()
      return when {
        handlesRotation && quarterTurn -> Geometry(format.height, format.width, 0, 1.0 / ratio)
        handlesRotation -> Geometry(format.width, format.height, 0, ratio)
        else -> Geometry(format.width, format.height, rotation, ratio)
      }
    }
    return Geometry(0, 0, 0, 1.0)
  }

  private data class Geometry(
      val width: Int,
      val height: Int,
      val rotationDegrees: Int,
      val pixelAspectRatio: Double,
  )

  private companion object {
    const val NO_SOURCE = -1L

    val MEDIA_AUDIO: AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build()
  }
}
