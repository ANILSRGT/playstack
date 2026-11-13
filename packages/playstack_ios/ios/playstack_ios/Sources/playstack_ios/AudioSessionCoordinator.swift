import AVFoundation
import Foundation

/// Applies the configured `AVAudioSession` category before the first audible
/// playback, and leaves the session alone when unmanaged (the default), so
/// the host app's audio configuration is respected.
final class AudioSessionCoordinator {
  private let config: PlatformEngineConfig
  private var activated = false

  init(config: PlatformEngineConfig) {
    self.config = config
  }

  var resumeAfterInterruption: Bool { config.resumeAfterInterruption }

  /// Called before a player starts. Errors are ignored on purpose: playback
  /// still works with the app's current session, only the category differs.
  func willPlay() {
    guard !activated else { return }
    let category: AVAudioSession.Category
    switch config.audioSessionCategory {
    case .unmanaged: return
    case .ambient: category = .ambient
    case .playback: category = .playback
    }
    activated = true
    let session = AVAudioSession.sharedInstance()
    var options: AVAudioSession.CategoryOptions = []
    if config.mixWithOthers || category == .ambient { options.insert(.mixWithOthers) }
    try? session.setCategory(category, mode: .moviePlayback, options: options)
    try? session.setActive(true)
  }
}

extension AudioSessionCoordinator {
  /// Sound in the background, the lock screen controls and
  /// Picture-in-Picture need the `playback` category without mixing: with
  /// another category iOS stops the video in the background and shows no
  /// controls. Called when the app turns one of them on.
  static func requireBackgroundPlayback() {
    let session = AVAudioSession.sharedInstance()
    let mixes = session.categoryOptions.contains(.mixWithOthers)
    if session.category == .playback && !mixes { return }
    if session.category == .playAndRecord && !mixes { return }
    try? session.setCategory(.playback, mode: .moviePlayback, options: [])
    try? session.setActive(true)
  }
}
