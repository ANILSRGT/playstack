import Flutter
import Foundation

/// Implements the ReelKit host API and owns every native player of one
/// Flutter engine. Pigeon delivers all calls on the main thread.
final class PlayerRegistry: ReelKitHostApi {
  private let textureRegistry: FlutterTextureRegistry
  private let events: PlayerEventDispatcher
  private var players: [Int64: NativePlayer] = [:]
  private var nextPlayerId: Int64 = 1
  private var capabilities: PlatformCapabilities?

  init(textureRegistry: FlutterTextureRegistry, events: PlayerEventDispatcher) {
    self.textureRegistry = textureRegistry
    self.events = events
  }

  func initialize() throws -> PlatformCapabilities {
    if let capabilities { return capabilities }
    let read = DeviceCapabilities.read()
    capabilities = read
    return read
  }

  func createPlayer(options: PlatformPlayerOptions) throws -> PlatformPlayerCreation {
    let id = nextPlayerId
    nextPlayerId += 1
    let player = NativePlayer(id: id, options: options)
    player.attach(to: textureRegistry)
    players[id] = player
    return PlatformPlayerCreation(playerId: id, textureId: player.textureId)
  }

  @MainActor
  func disposePlayer(playerId: Int64) async throws {
    players.removeValue(forKey: playerId)?.release(from: textureRegistry)
  }

  func setSource(playerId: Int64, source: PlatformSource, generation: Int64) throws {
    _ = try requirePlayer(playerId)
    throw notImplemented("setSource")
  }

  func play(playerId: Int64) throws {
    _ = try requirePlayer(playerId)
    throw notImplemented("play")
  }

  func pause(playerId: Int64) throws {
    _ = try requirePlayer(playerId)
    throw notImplemented("pause")
  }

  func seekTo(playerId: Int64, positionMs: Int64) async throws {
    _ = try requirePlayer(playerId)
    throw notImplemented("seekTo")
  }

  func setLooping(playerId: Int64, looping: Bool) throws {
    _ = try requirePlayer(playerId)
    throw notImplemented("setLooping")
  }

  func setVolume(playerId: Int64, volume: Double) throws {
    _ = try requirePlayer(playerId)
    throw notImplemented("setVolume")
  }

  func setPlaybackSpeed(playerId: Int64, speed: Double) throws {
    _ = try requirePlayer(playerId)
    throw notImplemented("setPlaybackSpeed")
  }

  func getPosition(playerId: Int64) throws -> PlatformPosition {
    _ = try requirePlayer(playerId)
    throw notImplemented("getPosition")
  }

  func releaseAll() {
    for player in players.values { player.release(from: textureRegistry) }
    players.removeAll()
  }

  private func requirePlayer(_ playerId: Int64) throws -> NativePlayer {
    guard let player = players[playerId] else {
      throw PigeonError(
        code: "playerNotFound", message: "No native player with id \(playerId).", details: nil)
    }
    return player
  }

  private func notImplemented(_ method: String) -> PigeonError {
    PigeonError(
      code: "notImplemented",
      message: "\(method) is not implemented yet by the ReelKit iOS engine "
        + "(scheduled for milestone 2: single native player).",
      details: nil)
  }
}
