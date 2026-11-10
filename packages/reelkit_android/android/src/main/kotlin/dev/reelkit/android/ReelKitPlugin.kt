package dev.reelkit.android

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Entry point of the ReelKit Android engine.
 *
 * Wires the typed Pigeon host API and the player event channel to a
 * [PlayerRegistry] that owns every native player created by this engine.
 */
class ReelKitPlugin : FlutterPlugin {
  private var registry: PlayerRegistry? = null
  private var events: PlayerEventDispatcher? = null
  private var eventChannel: PlayerEventsEventChannel? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val dispatcher = PlayerEventDispatcher()
    val playerRegistry =
        PlayerRegistry(
            context = binding.applicationContext,
            textureRegistry = binding.textureRegistry,
            flutterAssets = binding.flutterAssets,
            events = dispatcher,
        )
    ReelKitHostApi.setUp(binding.binaryMessenger, playerRegistry)
    eventChannel = PlayerEventsStreamHandler.register(binding.binaryMessenger, dispatcher)
    registry = playerRegistry
    events = dispatcher
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    ReelKitHostApi.setUp(binding.binaryMessenger, null)
    eventChannel?.setStreamHandler(null)
    registry?.releaseAll()
    events?.detach()
    eventChannel = null
    registry = null
    events = null
  }
}
