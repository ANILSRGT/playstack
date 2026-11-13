import Flutter
import UIKit

/// Entry point of the PlayStack iOS engine.
///
/// Wires the typed Pigeon host API and the player event channel to a
/// `PlayerRegistry` that owns every native player created by this engine.
public final class PlayStackPlugin: NSObject, FlutterPlugin {
  private let registry: PlayerRegistry
  private let events: PlayerEventDispatcher
  private let eventChannel: PlayerEventsEventChannel
  private let network: NetworkMonitor
  private let networkChannel: NetworkEventsEventChannel
  private let orientation: DeviceOrientationMonitor
  private let orientationChannel: DeviceOrientationEventsEventChannel
  private let systemEvents: SystemEvents
  private let systemChannel: SystemEventsEventChannel
  private let messenger: FlutterBinaryMessenger

  private init(registrar: FlutterPluginRegistrar) {
    messenger = registrar.messenger()
    events = PlayerEventDispatcher()
    network = NetworkMonitor()
    orientation = DeviceOrientationMonitor()
    systemEvents = SystemEvents()
    registry = PlayerRegistry(
      textureRegistry: registrar.textures(), events: events, network: network,
      orientation: orientation,
      systemEvents: systemEvents,
      assetLookup: { [weak registrar] name, package in
        guard let registrar else { return name }
        if let package { return registrar.lookupKey(forAsset: name, fromPackage: package) }
        return registrar.lookupKey(forAsset: name)
      })
    eventChannel = PlayerEventsStreamHandler.register(with: messenger, streamHandler: events)
    networkChannel = NetworkEventsStreamHandler.register(with: messenger, streamHandler: network)
    orientationChannel = DeviceOrientationEventsStreamHandler.register(
      with: messenger, streamHandler: orientation)
    systemChannel = SystemEventsStreamHandler.register(with: messenger, streamHandler: systemEvents)
    super.init()
    PlayStackHostApiSetup.setUp(binaryMessenger: messenger, api: registry)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PlayStackPlugin(registrar: registrar)
    registrar.publish(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    PlayStackHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    eventChannel.setStreamHandler(nil)
    networkChannel.setStreamHandler(nil)
    orientationChannel.setStreamHandler(nil)
    systemChannel.setStreamHandler(nil)
    systemEvents.detach()
    orientation.stop()
    network.stop()
    registry.releaseAll()
    events.detach()
  }
}
