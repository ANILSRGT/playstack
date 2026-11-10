package dev.reelkit.android

import android.content.Context
import io.flutter.view.TextureRegistry

/**
 * Implements the ReelKit host API and owns every native player of one Flutter
 * engine. All calls arrive on the platform thread.
 */
internal class PlayerRegistry(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    @Suppress("unused") private val events: PlayerEventDispatcher,
) : ReelKitHostApi {
  private val players = HashMap<Long, NativePlayer>()
  private var nextPlayerId = 1L
  private var capabilities: PlatformCapabilities? = null

  override fun initialize(): PlatformCapabilities =
      capabilities ?: DeviceCapabilities.read(context).also { capabilities = it }

  override fun createPlayer(options: PlatformPlayerOptions): PlatformPlayerCreation {
    val id = nextPlayerId++
    val producer = textureRegistry.createSurfaceProducer()
    val player =
        try {
          NativePlayer(id, context, producer, options)
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
    requirePlayer(playerId)
    throw notImplemented("setSource")
  }

  override fun play(playerId: Long) {
    requirePlayer(playerId)
    throw notImplemented("play")
  }

  override fun pause(playerId: Long) {
    requirePlayer(playerId)
    throw notImplemented("pause")
  }

  override suspend fun seekTo(playerId: Long, positionMs: Long) {
    requirePlayer(playerId)
    throw notImplemented("seekTo")
  }

  override fun setLooping(playerId: Long, looping: Boolean) {
    requirePlayer(playerId)
    throw notImplemented("setLooping")
  }

  override fun setVolume(playerId: Long, volume: Double) {
    requirePlayer(playerId)
    throw notImplemented("setVolume")
  }

  override fun setPlaybackSpeed(playerId: Long, speed: Double) {
    requirePlayer(playerId)
    throw notImplemented("setPlaybackSpeed")
  }

  override fun getPosition(playerId: Long): PlatformPosition {
    requirePlayer(playerId)
    throw notImplemented("getPosition")
  }

  fun releaseAll() {
    players.values.forEach { it.release() }
    players.clear()
  }

  private fun requirePlayer(playerId: Long): NativePlayer =
      players[playerId]
          ?: throw FlutterError("playerNotFound", "No native player with id $playerId.", null)

  private fun notImplemented(method: String) =
      FlutterError(
          "notImplemented",
          "$method is not implemented yet by the ReelKit Android engine " +
              "(scheduled for milestone 2: single native player).",
          null,
      )
}
