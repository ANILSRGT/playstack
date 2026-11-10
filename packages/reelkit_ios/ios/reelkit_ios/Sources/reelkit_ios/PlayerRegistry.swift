import Flutter
import Foundation

/// Implements the ReelKit host API and owns every native player of one
/// Flutter engine. Pigeon delivers all calls on the main thread.
final class PlayerRegistry: ReelKitHostApi {
  private let textureRegistry: FlutterTextureRegistry
  private let events: PlayerEventDispatcher
  private let network: NetworkMonitor
  private let sources: SourceResolver
  private var players: [Int64: NativePlayer] = [:]
  private var nextPlayerId: Int64 = 1
  private var capabilities: PlatformCapabilities?

  init(
    textureRegistry: FlutterTextureRegistry, events: PlayerEventDispatcher,
    network: NetworkMonitor,
    assetLookup: @escaping (String, String?) -> String
  ) {
    self.textureRegistry = textureRegistry
    self.events = events
    self.network = network
    sources = SourceResolver(assetLookup: assetLookup)
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
    let player = NativePlayer(
      id: id, options: options, events: events, textureRegistry: textureRegistry)
    players[id] = player
    return PlatformPlayerCreation(playerId: id, textureId: player.textureId)
  }

  @MainActor
  func disposePlayer(playerId: Int64) async throws {
    players.removeValue(forKey: playerId)?.release()
  }

  func setSource(playerId: Int64, source: PlatformSource, generation: Int64) throws {
    let player = try requirePlayer(playerId)
    player.setSource(try sources.resolve(source), generation: generation)
  }

  func clearSource(playerId: Int64) throws {
    try requirePlayer(playerId).clearSource()
  }

  func play(playerId: Int64) throws {
    try requirePlayer(playerId).play()
  }

  func pause(playerId: Int64) throws {
    try requirePlayer(playerId).pause()
  }

  @MainActor
  func seekTo(playerId: Int64, positionMs: Int64) async throws {
    let player = try requirePlayer(playerId)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      player.seek(toMilliseconds: positionMs) { continuation.resume() }
    }
  }

  func setPreloadBufferLimit(playerId: Int64, maxBufferMs: Int64?) throws {
    if let maxBufferMs, maxBufferMs < 0 {
      throw PigeonError(
        code: "invalidArgument", message: "Buffer limit must be >= 0, got \(maxBufferMs).",
        details: nil)
    }
    try requirePlayer(playerId).setPreloadBufferLimit(milliseconds: maxBufferMs)
  }

  func getNetworkStatus() throws -> PlatformNetworkStatus {
    network.current()
  }

  func setLooping(playerId: Int64, looping: Bool) throws {
    try requirePlayer(playerId).setLooping(looping)
  }

  func setVolume(playerId: Int64, volume: Double) throws {
    try requirePlayer(playerId).setVolume(volume)
  }

  func setPlaybackSpeed(playerId: Int64, speed: Double) throws {
    guard speed.isFinite, speed > 0 else {
      throw PigeonError(
        code: "invalidArgument", message: "Playback speed must be > 0, got \(speed).",
        details: nil)
    }
    try requirePlayer(playerId).setPlaybackSpeed(speed)
  }

  func getPosition(playerId: Int64) throws -> PlatformPosition {
    try requirePlayer(playerId).position()
  }

  func getTracks(playerId: Int64) throws -> [PlatformTrack] {
    try requirePlayer(playerId).tracks()
  }

  func selectTrack(playerId: Int64, type: PlatformTrackType, trackId: String?) throws {
    try requirePlayer(playerId).selectTrack(type: type, trackId: trackId)
  }

  func setVideoQualityLimit(
    playerId: Int64, maxBitrate: Int64?, maxWidth: Int64?, maxHeight: Int64?
  ) throws {
    try requirePlayer(playerId).setVideoQualityLimit(
      maxBitrate: maxBitrate, maxWidth: maxWidth, maxHeight: maxHeight)
  }

  func releaseAll() {
    for player in players.values { player.release() }
    players.removeAll()
  }

  private func requirePlayer(_ playerId: Int64) throws -> NativePlayer {
    guard let player = players[playerId] else {
      throw PigeonError(
        code: "playerNotFound", message: "No native player with id \(playerId).", details: nil)
    }
    return player
  }
}
