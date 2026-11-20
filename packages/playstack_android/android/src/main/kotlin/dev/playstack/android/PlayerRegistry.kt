package dev.playstack.android

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterAssets
import io.flutter.view.TextureRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Implements the PlayStack host API and owns every native player of one Flutter
 * engine. All calls arrive on the platform thread.
 */
internal class PlayerRegistry(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    flutterAssets: FlutterAssets,
    private val events: PlayerEventDispatcher,
    private val network: NetworkMonitor,
    private val orientation: DeviceOrientationMonitor,
    private val mediaSession: MediaSessionCoordinator,
    private val pictureInPicture: PictureInPictureCoordinator,
    private val downloads: DownloadCoordinator,
) : PlayStackHostApi {
  private val players = HashMap<Long, NativePlayer>()
  private var engineConfig: PlatformEngineConfig? = null
  private val sources = MediaSourceBuilder(context, flutterAssets) { engineConfig }
  private val frames = FrameExtractor(context, flutterAssets)
  private var nextPlayerId = 1L
  private var capabilities: PlatformCapabilities? = null

  /** The first call configures the engine; later calls share it. */
  override fun initialize(config: PlatformEngineConfig): PlatformCapabilities {
    if (engineConfig == null) engineConfig = config
    return capabilities ?: DeviceCapabilities.read(context).also { capabilities = it }
  }

  override fun createPlayer(options: PlatformPlayerOptions): PlatformPlayerCreation {
    val config = requireConfig()
    val id = nextPlayerId++
    val producer = textureRegistry.createSurfaceProducer()
    val player =
        try {
          NativePlayer(id, context, producer, events, options, config)
        } catch (error: RuntimeException) {
          producer.release()
          throw FlutterError("playerCreationFailed", error.message, error.toString())
        }
    players[id] = player
    return PlatformPlayerCreation(playerId = id, textureId = player.textureId)
  }

  override suspend fun disposePlayer(playerId: Long) {
    val player = players.remove(playerId) ?: return
    mediaSession.playerReleased(player)
    pictureInPicture.playerReleased(player)
    player.release()
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

  override fun setVideoDisabled(playerId: Long, disabled: Boolean) =
      requirePlayer(playerId).setVideoDisabled(disabled)

  override suspend fun seekToLiveEdge(playerId: Long) = requirePlayer(playerId).seekToLiveEdge()

  override fun getNetworkStatus(): PlatformNetworkStatus = network.current()

  override fun getAppOrientations(): List<PlatformOrientation> = orientation.appOrientations()

  override fun setMediaSession(playerId: Long?, info: PlatformMediaInfo?) =
      mediaSession.show(playerId?.let { players[it] }, info)

  override fun setPictureInPicture(playerId: Long?, autoEnter: Boolean) =
      pictureInPicture.setPlayer(playerId?.let { players[it] }, autoEnter)

  override fun startPictureInPicture(): Boolean = pictureInPicture.start()

  // The user leaves Picture-in-Picture; apps cannot end it.
  override fun stopPictureInPicture() {}

  override fun isPictureInPictureSupported(): Boolean = pictureInPicture.isSupported()

  override suspend fun getCacheInfo(): PlatformCacheInfo =
      withContext(Dispatchers.IO) {
        val config = engineConfig
        val enabled = config?.cacheEnabled == true
        PlatformCacheInfo(
            enabled = enabled,
            usedBytes = MediaCache.usedBytes(),
            maxBytes =
                if (MediaCache.existing() != null) MediaCache.configuredMaxBytes
                else if (enabled) config!!.cacheMaxBytes else 0,
        )
      }

  override suspend fun clearCache() = withContext(Dispatchers.IO) { MediaCache.clear() }

  override suspend fun removeCached(cacheKey: String) =
      withContext(Dispatchers.IO) { MediaCache.remove(cacheKey) }

  override suspend fun getCachedBytes(cacheKey: String): Long =
      withContext(Dispatchers.IO) { MediaCache.cachedBytes(cacheKey) }

  override fun isDownloadSupported(): Boolean = true

  override fun setDownloadsEnabled(enabled: Boolean) = downloads.setEnabled(enabled)

  override fun startDownload(request: PlatformDownloadRequest) = downloads.start(request)

  override fun pauseDownload(id: String) = downloads.pause(id)

  override fun resumeDownload(id: String) = downloads.resume(id)

  override fun removeDownload(id: String) = downloads.remove(id)

  override fun getDownloads(): List<PlatformDownload> = downloads.all()

  private fun requireConfig(): PlatformEngineConfig =
      engineConfig
          ?: throw FlutterError("notInitialized", "Call initialize() before createPlayer().", null)

  override suspend fun getFrame(
      source: PlatformSource,
      positionMs: Long,
      maxWidth: Long
  ): ByteArray? = frames.frame(source, positionMs, maxWidth)

  override fun getScreenBrightness(): Double {
    val override = orientation.activity?.window?.attributes?.screenBrightness ?: -1f
    if (override >= 0f) return override.toDouble()
    return try {
      android.provider.Settings.System.getInt(
          context.contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS) / 255.0
    } catch (error: android.provider.Settings.SettingNotFoundException) {
      0.5
    }
  }

  override fun setScreenBrightness(brightness: Double?) {
    val window = orientation.activity?.window ?: return
    window.attributes =
        window.attributes.apply {
          screenBrightness =
              brightness?.toFloat()?.coerceIn(0.01f, 1f)
                  ?: android.view.WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        }
  }

  /** The player with [id], for platform views. */
  fun player(id: Long): NativePlayer? = players[id]

  fun releaseAll() {
    mediaSession.clear()
    pictureInPicture.setPlayer(null, false)
    players.values.forEach { it.release() }
    players.clear()
    frames.release()
  }

  private fun requirePlayer(playerId: Long): NativePlayer =
      players[playerId]
          ?: throw FlutterError("playerNotFound", "No native player with id $playerId.", null)
}
