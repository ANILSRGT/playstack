import AVFoundation
import AVKit
import Flutter
import MediaPlayer
import UIKit

/// Sends media control commands and Picture-in-Picture changes to Dart.
final class SystemEvents: SystemEventsStreamHandler {
  private var sink: PigeonEventSink<PlatformSystemEvent>?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<PlatformSystemEvent>) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func emit(_ type: PlatformSystemEventType, positionMs: Int64? = nil) {
    sink?.success(PlatformSystemEvent(type: type, positionMs: positionMs))
  }

  func detach() {
    sink = nil
  }
}

/// The lock screen, Control Center, headphone and car controls of one
/// player: `MPNowPlayingInfoCenter` for what is shown, `MPRemoteCommandCenter`
/// for the buttons. Commands go to Dart, which drives the player.
final class MediaSessionCoordinator {
  private let events: SystemEvents
  private weak var player: NativePlayer?
  private var info: PlatformMediaInfo?
  private var artwork: MPMediaItemArtwork?
  private var artworkUrl: String?
  private var artworkTask: URLSessionDataTask?
  private var targets: [(MPRemoteCommand, Any)] = []

  init(events: SystemEvents) {
    self.events = events
  }

  func show(_ player: NativePlayer?, info: PlatformMediaInfo?) {
    guard let player, let info else {
      clear()
      return
    }
    AudioSessionCoordinator.requireBackgroundPlayback()
    if self.player !== player { self.player?.onPlaybackChange = nil }
    self.player = player
    self.info = info
    player.onPlaybackChange = { [weak self] in self?.update() }
    registerCommands()
    let center = MPRemoteCommandCenter.shared()
    center.nextTrackCommand.isEnabled = info.canSkipNext
    center.previousTrackCommand.isEnabled = info.canSkipPrevious
    if info.artworkUrl != artworkUrl {
      artworkUrl = info.artworkUrl
      artwork = nil
      loadArtwork()
    }
    update()
  }

  func clear() {
    player?.onPlaybackChange = nil
    player = nil
    info = nil
    artworkTask?.cancel()
    artworkTask = nil
    artwork = nil
    artworkUrl = nil
    for (command, target) in targets { command.removeTarget(target) }
    targets.removeAll()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  func playerReleased(_ released: NativePlayer) {
    if released === player { clear() }
  }

  private func update() {
    guard let player, let info else { return }
    var values: [String: Any] = [
      MPNowPlayingInfoPropertyElapsedPlaybackTime: player.positionSeconds,
      MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? Double(player.avPlayer.rate) : 0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
    ]
    if let title = info.title { values[MPMediaItemPropertyTitle] = title }
    if let artist = info.artist { values[MPMediaItemPropertyArtist] = artist }
    if let album = info.album { values[MPMediaItemPropertyAlbumTitle] = album }
    if let duration = player.durationSeconds {
      values[MPMediaItemPropertyPlaybackDuration] = duration
    } else {
      values[MPNowPlayingInfoPropertyIsLiveStream] = true
    }
    if let artwork { values[MPMediaItemPropertyArtwork] = artwork }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = values
  }

  private func registerCommands() {
    guard targets.isEmpty else { return }
    let center = MPRemoteCommandCenter.shared()
    func add(_ command: MPRemoteCommand, _ handler: @escaping (MPRemoteCommandEvent) -> Void) {
      command.isEnabled = true
      let target = command.addTarget { event in
        handler(event)
        return .success
      }
      targets.append((command, target))
    }
    add(center.playCommand) { [weak self] _ in self?.events.emit(.play) }
    add(center.pauseCommand) { [weak self] _ in self?.events.emit(.pause) }
    add(center.togglePlayPauseCommand) { [weak self] _ in
      guard let self else { return }
      self.events.emit(self.player?.isPlaying == true ? .pause : .play)
    }
    add(center.changePlaybackPositionCommand) { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return }
      self?.events.emit(.seek, positionMs: Int64((event.positionTime * 1000).rounded()))
    }
    add(center.nextTrackCommand) { [weak self] _ in self?.events.emit(.next) }
    add(center.previousTrackCommand) { [weak self] _ in self?.events.emit(.previous) }
  }

  private func loadArtwork() {
    artworkTask?.cancel()
    artworkTask = nil
    guard let string = artworkUrl, let url = URL(string: string),
      url.scheme == "http" || url.scheme == "https"
    else { return }
    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        guard let self, self.artworkUrl == string else { return }
        self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.update()
      }
    }
    artworkTask = task
    task.resume()
  }
}

/// Picture-in-Picture of one player through `AVPictureInPictureController`.
///
/// The engine draws video into Flutter textures, which Picture-in-Picture
/// cannot use, so an `AVPlayerLayer` of the same `AVPlayer` is placed in
/// the window behind the Flutter view, where it is not seen, for the
/// system to take over. With auto-enter, Picture-in-Picture starts when the
/// app resigns active while the video plays.
final class PictureInPictureCoordinator: NSObject, AVPictureInPictureControllerDelegate {
  private let events: SystemEvents
  private weak var player: NativePlayer?
  private var layer: AVPlayerLayer?
  private var controller: AVPictureInPictureController?
  private var possibleObservation: NSKeyValueObservation?
  private var autoEnter = false
  private var startWhenPossible = false
  private var reportedActive = false
  /// Reported as started on resigning active, before the system starts it.
  private var provisional = false
  private var observers: [NSObjectProtocol] = []

  init(events: SystemEvents) {
    self.events = events
    super.init()
    let center = NotificationCenter.default
    observers = [
      center.addObserver(
        forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.onWillResignActive() },
      center.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.settleProvisional() },
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        // The system starts it right after the app leaves; if it has not by
        // now, it will not.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.settleProvisional() }
      },
    ]
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

  func setPlayer(_ player: NativePlayer?, autoEnter: Bool) {
    self.autoEnter = autoEnter
    if player != nil, player === self.player, let controller {
      controller.canStartPictureInPictureAutomaticallyFromInline = autoEnter
      return
    }
    teardown()
    guard let player, PictureInPictureCoordinator.isSupported,
      let window = PictureInPictureCoordinator.keyWindow()
    else { return }
    AudioSessionCoordinator.requireBackgroundPlayback()
    self.player = player
    let layer = AVPlayerLayer(player: player.avPlayer)
    layer.videoGravity = .resizeAspect
    layer.frame = window.bounds
    // Behind the Flutter view: in the window, so that the system can use
    // it, but never seen.
    window.layer.insertSublayer(layer, at: 0)
    self.layer = layer
    guard let controller = AVPictureInPictureController(playerLayer: layer) else {
      teardown()
      return
    }
    controller.delegate = self
    // The system starts it when the app goes to the background.
    controller.canStartPictureInPictureAutomaticallyFromInline = autoEnter
    possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) {
      [weak self] controller, _ in
      DispatchQueue.main.async {
        guard let self, self.startWhenPossible, controller.isPictureInPicturePossible else {
          return
        }
        self.startWhenPossible = false
        controller.startPictureInPicture()
      }
    }
    self.controller = controller
  }

  func start() -> Bool {
    guard let controller else { return false }
    if controller.isPictureInPictureActive { return true }
    if controller.isPictureInPicturePossible {
      controller.startPictureInPicture()
    } else {
      // Possible shortly after the layer got its first frame.
      startWhenPossible = true
    }
    return true
  }

  func stop() {
    startWhenPossible = false
    controller?.stopPictureInPicture()
  }

  func playerReleased(_ released: NativePlayer) {
    if released === player { teardown() }
  }

  /// The system starts Picture-in-Picture itself when the app goes to the
  /// background (`canStartPictureInPictureAutomaticallyFromInline`). Dart is
  /// told before the app's lifecycle reaches it, so that the video is not
  /// paused for going to the background; [settleProvisional] takes it back
  /// when the system did not start it.
  private func onWillResignActive() {
    guard autoEnter, let player, player.isPlaying, let controller,
      controller.isPictureInPicturePossible, !controller.isPictureInPictureActive
    else { return }
    provisional = true
    report(active: true)
  }

  private func settleProvisional() {
    guard provisional else { return }
    provisional = false
    if controller?.isPictureInPictureActive != true { report(active: false) }
  }

  private func teardown() {
    startWhenPossible = false
    provisional = false
    possibleObservation?.invalidate()
    possibleObservation = nil
    if let controller, controller.isPictureInPictureActive { controller.stopPictureInPicture() }
    controller?.delegate = nil
    controller = nil
    layer?.player = nil
    layer?.removeFromSuperlayer()
    layer = nil
    player = nil
    report(active: false)
  }

  private func report(active: Bool) {
    guard active != reportedActive else { return }
    reportedActive = active
    events.emit(active ? .pictureInPictureStarted : .pictureInPictureStopped)
  }

  private static func keyWindow() -> UIWindow? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first(where: { $0.isKeyWindow }) ?? windows.first
  }

  // MARK: AVPictureInPictureControllerDelegate

  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    provisional = false
    report(active: true)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    provisional = false
    report(active: false)
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    report(active: false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }
}
