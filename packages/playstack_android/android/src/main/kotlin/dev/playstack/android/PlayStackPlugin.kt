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
  private var systemEvents: SystemEvents? = null
  private var systemChannel: SystemEventsEventChannel? = null
  private var mediaSession: MediaSessionCoordinator? = null
  private var pictureInPicture: PictureInPictureCoordinator? = null
  private var activityBinding: ActivityPluginBinding? = null
  private val userLeaveHint = io.flutter.plugin.common.PluginRegistry.UserLeaveHintListener {
    pictureInPicture?.onUserLeaveHint()
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val dispatcher = PlayerEventDispatcher()
    val networkMonitor = NetworkMonitor(binding.applicationContext)
    val orientationMonitor = DeviceOrientationMonitor(binding.applicationContext)
    val system = SystemEvents()
    val session = MediaSessionCoordinator(binding.applicationContext, system)
    val pip = PictureInPictureCoordinator(system)
    val playerRegistry =
        PlayerRegistry(
            context = binding.applicationContext,
            textureRegistry = binding.textureRegistry,
            flutterAssets = binding.flutterAssets,
            events = dispatcher,
            network = networkMonitor,
            orientation = orientationMonitor,
            mediaSession = session,
            pictureInPicture = pip,
        )
    PlayStackHostApi.setUp(binding.binaryMessenger, playerRegistry)
    eventChannel = PlayerEventsStreamHandler.register(binding.binaryMessenger, dispatcher)
    networkChannel = NetworkEventsStreamHandler.register(binding.binaryMessenger, networkMonitor)
    orientationChannel =
        DeviceOrientationEventsStreamHandler.register(binding.binaryMessenger, orientationMonitor)
    orientation = orientationMonitor
    systemChannel = SystemEventsStreamHandler.register(binding.binaryMessenger, system)
    systemEvents = system
    mediaSession = session
    pictureInPicture = pip
    registry = playerRegistry
    events = dispatcher
    network = networkMonitor
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    PlayStackHostApi.setUp(binding.binaryMessenger, null)
    eventChannel?.setStreamHandler(null)
    networkChannel?.setStreamHandler(null)
    orientationChannel?.setStreamHandler(null)
    systemChannel?.setStreamHandler(null)
    systemEvents?.detach()
    orientation?.stop()
    network?.stop()
    registry?.releaseAll()
    events?.detach()
    eventChannel = null
    networkChannel = null
    orientationChannel = null
    orientation = null
    systemChannel = null
    systemEvents = null
    mediaSession = null
    pictureInPicture = null
    network = null
    registry = null
    events = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) = attachActivity(binding)

  override fun onDetachedFromActivityForConfigChanges() = detachActivity()

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
      attachActivity(binding)

  override fun onDetachedFromActivity() = detachActivity()

  private fun attachActivity(binding: ActivityPluginBinding) {
    detachActivity()
    activityBinding = binding
    orientation?.activity = binding.activity
    pictureInPicture?.attach(binding.activity)
    binding.addOnUserLeaveHintListener(userLeaveHint)
  }

  private fun detachActivity() {
    activityBinding?.removeOnUserLeaveHintListener(userLeaveHint)
    activityBinding = null
    orientation?.activity = null
    pictureInPicture?.detach()
  }
}
