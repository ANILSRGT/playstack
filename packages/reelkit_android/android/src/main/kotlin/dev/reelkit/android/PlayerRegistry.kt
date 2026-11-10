package dev.reelkit.android

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterAssets
import io.flutter.view.TextureRegistry

/**
 * Implements the ReelKit host API and owns every native player of one Flutter
 * engine. All calls arrive on the platform thread.
 */
internal class PlayerRegistry(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    flutterAssets: FlutterAssets,
    private val events: PlayerEventDispatcher,
    private val network: NetworkMonitor,
) : ReelKitHostApi {
  private val players = HashMap<Long, NativePlayer>()
  private val sources = MediaSourceBuilder(context, flutterAssets)
  private var nextPlayerId = 1L
  private var capabilities: PlatformCapabilities? = null

  override fun initialize(): PlatformCapabilities =
      capabilities ?: DeviceCapabilities.read(context).also { capabilities = it }

  override fun createPlayer(options: PlatformPlayerOptions): PlatformPlayerCreation {
    val id = nextPlayerId++
    val producer = textureRegistry.createSurfaceProducer()
    val player =
        try {
          NativePlayer(id, context, producer, events, options)
        } catch (error: RuntimeException) {
          producer.release()
          throw FlutterError("playerCreationFailed", error.message, error.toString())
        }
    players[id] = player
    return PlatformPlayerCreation(playerId = id, textureId = player.textureId)
  }

  override suspend fun disposePlayer(playerId: Long) {
    players.remove(playerId)?.release()
  }

  override fun setSource(playerId: Long, source: PlatformSource, generation: Long) {
    val player = requirePlayer(playerId)
    player.setSource(sources.build(source), generation)
  }

  override fun clearSource(playerId: Long) = requirePlayer(playerId).clearSource()

  override fun play(playerId: Long) = requirePlayer(playerId).play()

  override fun pause(playerId: Long) = requirePlayer(playerId).pause()

  override suspend fun seekTo(playerId: Long, positionMs: Long) =
      requirePlayer(playerId).seekTo(positionMs)

  override fun setLooping(playerId: Long, looping: Boolean) =
      requirePlayer(playerId).setLooping(looping)

  override fun setVolume(playerId: Long, volume: Double) =
      requirePlayer(playerId).setVolume(volume)

  override fun setPlaybackSpeed(playerId: Long, speed: Double) {
    if (!speed.isFinite() || speed <= 0) {
      throw FlutterError("invalidArgument", "Playback speed must be > 0, got $speed.", null)
    }
    requirePlayer(playerId).setPlaybackSpeed(speed)
  }

  override fun getPosition(playerId: Long): PlatformPosition = requirePlayer(playerId).position()

  override fun getTracks(playerId: Long): List<PlatformTrack> = requirePlayer(playerId).tracks()

  override fun selectTrack(playerId: Long, type: PlatformTrackType, trackId: String?) =
      requirePlayer(playerId).selectTrack(type, trackId)

  override fun setVideoQualityLimit(
      playerId: Long,
      maxBitrate: Long?,
      maxWidth: Long?,
      maxHeight: Long?,
  ) = requirePlayer(playerId).setVideoQualityLimit(maxBitrate, maxWidth, maxHeight)

  override fun setPreloadBufferLimit(playerId: Long, maxBufferMs: Long?) {
    if (maxBufferMs != null && maxBufferMs < 0) {
      throw FlutterError("invalidArgument", "Buffer limit must be >= 0, got $maxBufferMs.", null)
    }
    requirePlayer(playerId).setPreloadBufferLimit(maxBufferMs)
  }

  override fun getNetworkStatus(): PlatformNetworkStatus = network.current()

  fun releaseAll() {
    players.values.forEach { it.release() }
    players.clear()
  }

  private fun requirePlayer(playerId: Long): NativePlayer =
      players[playerId]
          ?: throw FlutterError("playerNotFound", "No native player with id $playerId.", null)
}
