package dev.playstack.android

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Entry point of the PlayStack Android engine.
 *
 * Wires the typed Pigeon host API and the player event channel to a
 * [PlayerRegistry] that owns every native player created by this engine.
 */
class PlayStackPlugin : FlutterPlugin {
  private var registry: PlayerRegistry? = null
  private var events: PlayerEventDispatcher? = null
  private var eventChannel: PlayerEventsEventChannel? = null
  private var network: NetworkMonitor? = null
  private var networkChannel: NetworkEventsEventChannel? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val dispatcher = PlayerEventDispatcher()
    val networkMonitor = NetworkMonitor(binding.applicationContext)
    val playerRegistry =
        PlayerRegistry(
            context = binding.applicationContext,
            textureRegistry = binding.textureRegistry,
            flutterAssets = binding.flutterAssets,
            events = dispatcher,
            network = networkMonitor,
        )
    PlayStackHostApi.setUp(binding.binaryMessenger, playerRegistry)
    eventChannel = PlayerEventsStreamHandler.register(binding.binaryMessenger, dispatcher)
    networkChannel = NetworkEventsStreamHandler.register(binding.binaryMessenger, networkMonitor)
    registry = playerRegistry
    events = dispatcher
    network = networkMonitor
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    PlayStackHostApi.setUp(binding.binaryMessenger, null)
    eventChannel?.setStreamHandler(null)
    networkChannel?.setStreamHandler(null)
    network?.stop()
    registry?.releaseAll()
    events?.detach()
    eventChannel = null
    networkChannel = null
    network = null
    registry = null
    events = null
  }
}
