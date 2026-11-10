package dev.reelkit.android

import android.content.Context
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.view.TextureRegistry

/**
 * One Media3 [ExoPlayer] bound to one Flutter [TextureRegistry.SurfaceProducer].
 *
 * The surface producer may destroy and recreate its surface (for example when
 * the app is backgrounded on Impeller); the callback keeps ExoPlayer pointed
 * at the current surface instead of caching a stale one.
 */
internal class NativePlayer(
    val id: Long,
    context: Context,
    private val surfaceProducer: TextureRegistry.SurfaceProducer,
    options: PlatformPlayerOptions,
) {
  private val exoPlayer: ExoPlayer = ExoPlayer.Builder(context).build()
  private var released = false

  val textureId: Long
    get() = surfaceProducer.id()

  init {
    exoPlayer.repeatMode = if (options.looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    exoPlayer.volume = options.volume.toFloat().coerceIn(0f, 1f)
    exoPlayer.setPlaybackSpeed(options.playbackSpeed.toFloat())

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

  fun release() {
    if (released) return
    released = true
    surfaceProducer.setCallback(null)
    exoPlayer.setVideoSurface(null)
    exoPlayer.release()
    surfaceProducer.release()
  }
}
