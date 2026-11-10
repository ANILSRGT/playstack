import Flutter
import UIKit

/// Entry point of the ReelKit iOS engine.
///
/// Wires the typed Pigeon host API and the player event channel to a
/// `PlayerRegistry` that owns every native player created by this engine.
public final class ReelKitPlugin: NSObject, FlutterPlugin {
  private let registry: PlayerRegistry
  private let events: PlayerEventDispatcher
  private let eventChannel: PlayerEventsEventChannel
  private let messenger: FlutterBinaryMessenger

  private init(registrar: FlutterPluginRegistrar) {
    messenger = registrar.messenger()
    events = PlayerEventDispatcher()
    registry = PlayerRegistry(textureRegistry: registrar.textures(), events: events)
    eventChannel = PlayerEventsStreamHandler.register(with: messenger, streamHandler: events)
    super.init()
    ReelKitHostApiSetup.setUp(binaryMessenger: messenger, api: registry)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ReelKitPlugin(registrar: registrar)
    registrar.publish(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    ReelKitHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    eventChannel.setStreamHandler(nil)
    registry.releaseAll()
    events.detach()
  }
}
