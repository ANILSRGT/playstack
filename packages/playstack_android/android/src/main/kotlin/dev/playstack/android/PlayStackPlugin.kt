package dev.playstack.android

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Entry point of the PlayStack Android engine.
 *
 * Wires the typed Pigeon host API and the player event channel to a
 * [PlayerRegistry] that owns every native player created by this engine.
 */
class PlayStackPlugin : FlutterPlugin, ActivityAware {
  private var registry: PlayerRegistry? = null
  private var events: PlayerEventDispatcher? = null
  private var eventChannel: PlayerEventsEventChannel? = null
  private var network: NetworkMonitor? = null
  private var networkChannel: NetworkEventsEventChannel? = null
  private var orientation: DeviceOrientationMonitor? = null
  private var orientationChannel: DeviceOrientationEventsEventChannel? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val dispatcher = PlayerEventDispatcher()
    val networkMonitor = NetworkMonitor(binding.applicationContext)
    val orientationMonitor = DeviceOrientationMonitor(binding.applicationContext)
    val playerRegistry =
        PlayerRegistry(
            context = binding.applicationContext,
            textureRegistry = binding.textureRegistry,
            flutterAssets = binding.flutterAssets,
            events = dispatcher,
            network = networkMonitor,
            orientation = orientationMonitor,
        )
    PlayStackHostApi.setUp(binding.binaryMessenger, playerRegistry)
    eventChannel = PlayerEventsStreamHandler.register(binding.binaryMessenger, dispatcher)
    networkChannel = NetworkEventsStreamHandler.register(binding.binaryMessenger, networkMonitor)
    orientationChannel =
        DeviceOrientationEventsStreamHandler.register(binding.binaryMessenger, orientationMonitor)
    orientation = orientationMonitor
    registry = playerRegistry
    events = dispatcher
    network = networkMonitor
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    PlayStackHostApi.setUp(binding.binaryMessenger, null)
    eventChannel?.setStreamHandler(null)
    networkChannel?.setStreamHandler(null)
    orientationChannel?.setStreamHandler(null)
    orientation?.stop()
    network?.stop()
    registry?.releaseAll()
    events?.detach()
    eventChannel = null
    networkChannel = null
    orientationChannel = null
    orientation = null
    network = null
    registry = null
    events = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    orientation?.activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    orientation?.activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    orientation?.activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    orientation?.activity = null
  }
}
