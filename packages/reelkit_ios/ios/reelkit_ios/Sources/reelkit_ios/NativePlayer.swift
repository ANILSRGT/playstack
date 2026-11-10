import AVFoundation
import Flutter
import QuartzCore

/// One `AVPlayer` rendered into one Flutter texture.
///
/// Rendering uses `AVPlayerItemVideoOutput` + `FlutterTexture` rather than an
/// `AVPlayerLayer` platform view: IOSurface-backed pixel buffers are imported
/// by the Flutter engine without a copy, and the video composes with arbitrary
/// Flutter widgets without the overlay and thread-merging costs that platform
/// views add inside scrolling feeds.
///
/// A display link pulls frames only while playback is requested or a new
/// frame is expected (after a source change or a seek); a paused player costs
/// no per-frame work.
///
/// All methods must be called on the main thread.
final class NativePlayer: NSObject, FlutterTexture, AVPlayerItemLegibleOutputPushDelegate {
  let id: Int64
  private(set) var textureId: Int64 = 0

  private let player = AVPlayer()
  private let events: PlayerEventDispatcher
  private weak var textureRegistry: FlutterTextureRegistry?

  private var looping: Bool
  private var playbackSpeed: Float

  private var item: AVPlayerItem?
  private var videoOutput: AVPlayerItemVideoOutput?
  private var legibleOutput: AVPlayerItemLegibleOutput?
  private var temporaryFile: URL?
  private var itemObservations: [NSKeyValueObservation] = []
  private var itemNotifications: [NSObjectProtocol] = []
  private var playerObservations: [NSKeyValueObservation] = []

  private var generation: Int64 = NativePlayer.noSource
  private var initializedSent = false
  private var firstFrameSent = false
  private var awaitingFrame = false
  private var lastReportedPlaying = false
  private var rotationDegrees: Int64 = 0
  private var pixelAspectRatio: Double = 1

  private var displayLink: CADisplayLink?
  private var latestPixelBuffer: CVPixelBuffer?
  private let pixelBufferLock = NSLock()
  private var released = false

  private static let noSource: Int64 = -1

  init(
    id: Int64, options: PlatformPlayerOptions, events: PlayerEventDispatcher,
    textureRegistry: FlutterTextureRegistry
  ) {
    self.id = id
    self.events = events
    self.textureRegistry = textureRegistry
    looping = options.looping
    playbackSpeed = Float(options.playbackSpeed)
    super.init()
    player.volume = Float(min(max(options.volume, 0), 1))
    player.actionAtItemEnd = .pause
    textureId = textureRegistry.register(self)
    observePlayer()
  }

  // MARK: Commands

  func setSource(_ resolved: SourceResolver.Resolved, generation: Int64) {
    detachItem()
    self.generation = generation
    temporaryFile = resolved.temporaryFile

    let item = AVPlayerItem(asset: resolved.asset)
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ])
    item.add(output)
    // Subtitles are delivered as text to Dart; AVFoundation must not draw
    // them (it could not anyway: frames go through the video output).
    let legible = AVPlayerItemLegibleOutput()
    legible.suppressesPlayerRendering = true
    legible.setDelegate(self, queue: .main)
    item.add(legible)
    self.item = item
    videoOutput = output
    legibleOutput = legible
    observe(item)
    player.replaceCurrentItem(with: item)
    awaitingFrame = true
    updateDisplayLink()
  }

  func clearSource() {
    detachItem()
    clearPixelBuffer()
  }

  func play() {
    player.rate = playbackSpeed
  }

  func pause() {
    player.pause()
  }

  func seek(toMilliseconds positionMs: Int64, completion: @escaping () -> Void) {
    let time = CMTime(value: positionMs, timescale: 1000)
    awaitingFrame = true
    updateDisplayLink()
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
      DispatchQueue.main.async(execute: completion)
    }
  }

  func setLooping(_ looping: Bool) {
    self.looping = looping
  }

  func setVolume(_ volume: Double) {
    player.volume = Float(min(max(volume, 0), 1))
  }

  func setPlaybackSpeed(_ speed: Double) {
    playbackSpeed = Float(speed)
    if player.rate != 0 { player.rate = playbackSpeed }
  }

  func tracks() -> [PlatformTrack] {
    guard let item, initializedSent else { return [] }
    return TrackSelection.list(item)
  }

  func selectTrack(type: PlatformTrackType, trackId: String?) throws {
    guard let item, initializedSent else {
      throw PigeonError(code: "notInitialized", message: "No prepared source.", details: nil)
    }
    try TrackSelection.select(item, type: type, trackId: trackId)
    if type == .text && trackId == nil { emitCues([]) }
  }

  func setVideoQualityLimit(maxBitrate: Int64?, maxWidth: Int64?, maxHeight: Int64?) {
    guard let item else { return }
    TrackSelection.limitVideo(item, maxBitrate: maxBitrate, maxWidth: maxWidth, maxHeight: maxHeight)
  }

  // MARK: AVPlayerItemLegibleOutputPushDelegate

  func legibleOutput(
    _ output: AVPlayerItemLegibleOutput,
    didOutputAttributedStrings strings: [NSAttributedString],
    nativeSampleBuffers nativeSamples: [Any], forItemTime itemTime: CMTime
  ) {
    guard output === legibleOutput else { return }
    emitCues(strings.map { $0.string }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
  }

  private func emitCues(_ texts: [String]) {
    guard generation != NativePlayer.noSource else { return }
    events.emit(PlatformCuesEvent(playerId: id, generation: generation, texts: texts))
  }

  func position() -> PlatformPosition {
    let current = player.currentTime()
    let positionMs = milliseconds(current)
    var bufferedMs = positionMs
    if let ranges = item?.loadedTimeRanges {
      for value in ranges {
        let range = value.timeRangeValue
        if range.containsTime(current) || range.start > current {
          bufferedMs = max(bufferedMs, milliseconds(range.end))
          break
        }
      }
    }
    return PlatformPosition(positionMs: positionMs, bufferedMs: bufferedMs)
  }

  func release() {
    guard !released else { return }
    released = true
    detachItem()
    playerObservations.forEach { $0.invalidate() }
    playerObservations.removeAll()
    stopDisplayLink()
    clearPixelBuffer()
    textureRegistry?.unregisterTexture(textureId)
  }

  // MARK: FlutterTexture

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    pixelBufferLock.lock()
    defer { pixelBufferLock.unlock() }
    guard let buffer = latestPixelBuffer else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  // MARK: Observation

  private func observePlayer() {
    playerObservations = [
      player.observe(\.rate, options: [.new]) { [weak self] player, _ in
        let isPlaying = player.rate != 0
        DispatchQueue.main.async { self?.reportPlaying(isPlaying) }
      },
      player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
        let status = player.timeControlStatus
        DispatchQueue.main.async { self?.onTimeControlStatus(status) }
      },
    ]
  }

  private func observe(_ item: AVPlayerItem) {
    itemObservations = [
      item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
        DispatchQueue.main.async {
          guard let self, let item, item === self.item else { return }
          self.onItemStatus(item)
        }
      },
      item.observe(\.presentationSize, options: [.new]) { [weak self, weak item] _, _ in
        DispatchQueue.main.async {
          guard let self, let item, item === self.item, self.initializedSent else { return }
          self.emitVideoSize(for: item)
        }
      },
    ]
    let center = NotificationCenter.default
    itemNotifications = [
      center.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
      ) { [weak self] _ in self?.onPlayedToEnd() },
      center.addObserver(
        forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: item, queue: .main
      ) { [weak self] _ in
        guard let self, self.initializedSent, self.generation != NativePlayer.noSource else {
          return
        }
        self.events.emit(
          PlatformTracksChangedEvent(playerId: self.id, generation: self.generation))
      },
      center.addObserver(
        forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
      ) { [weak self] note in
        let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        self?.emitError(error)
      },
    ]
  }

  private func onItemStatus(_ item: AVPlayerItem) {
    switch item.status {
    case .readyToPlay:
      guard !initializedSent else { return }
      initializedSent = true
      readGeometry(of: item)
      let size = frameSize(of: item)
      let duration = item.duration
      let videoTrack = item.tracks.compactMap({ $0.assetTrack }).first(where: {
        $0.mediaType == .video
      })
      events.emit(
        PlatformInitializedEvent(
          playerId: id, generation: generation,
          durationMs: duration.isNumeric ? milliseconds(duration) : -1,
          isLive: duration.isIndefinite,
          frameRate: videoTrack.flatMap {
            $0.nominalFrameRate > 0 ? Double($0.nominalFrameRate) : nil
          },
          bitrate: videoTrack.flatMap {
            $0.estimatedDataRate > 0 ? Int64($0.estimatedDataRate) : nil
          },
          videoCodec: videoTrack.flatMap(TrackSelection.codec(of:)),
          width: Int64(size.width), height: Int64(size.height),
          rotationDegrees: rotationDegrees, pixelAspectRatio: pixelAspectRatio))
      emitState(player.timeControlStatus == .waitingToPlayAtSpecifiedRate ? .buffering : .ready)
      updateDisplayLink()
    case .failed:
      emitError(item.error)
    default:
      break
    }
  }

  private func onTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
    guard generation != NativePlayer.noSource, initializedSent else {
      updateDisplayLink()
      return
    }
    switch status {
    case .waitingToPlayAtSpecifiedRate: emitState(.buffering)
    case .playing: emitState(.ready)
    case .paused: break
    @unknown default: break
    }
    updateDisplayLink()
  }

  private func reportPlaying(_ isPlaying: Bool) {
    updateDisplayLink()
    guard generation != NativePlayer.noSource, isPlaying != lastReportedPlaying else { return }
    lastReportedPlaying = isPlaying
    events.emit(PlatformIsPlayingEvent(playerId: id, generation: generation, isPlaying: isPlaying))
  }

  private func onPlayedToEnd() {
    guard generation != NativePlayer.noSource else { return }
    if looping {
      awaitingFrame = true
      player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
        DispatchQueue.main.async {
          guard let self, self.looping else { return }
          self.player.rate = self.playbackSpeed
        }
      }
      return
    }
    emitState(.ended)
  }

  // MARK: Display link

  private func updateDisplayLink() {
    let needed =
      !released && videoOutput != nil && (player.rate != 0 || awaitingFrame)
    if needed { startDisplayLink() } else { stopDisplayLink() }
  }

  private func startDisplayLink() {
    guard displayLink == nil else { return }
    let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  private func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
  }

  fileprivate func onDisplayLink() {
    guard let output = videoOutput else {
      stopDisplayLink()
      return
    }
    let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
    if output.hasNewPixelBuffer(forItemTime: itemTime),
      let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
    {
      pixelBufferLock.lock()
      latestPixelBuffer = buffer
      pixelBufferLock.unlock()
      textureRegistry?.textureFrameAvailable(textureId)
      awaitingFrame = false
      if !firstFrameSent, generation != NativePlayer.noSource {
        firstFrameSent = true
        events.emit(PlatformFirstFrameEvent(playerId: id, generation: generation))
      }
    }
    updateDisplayLink()
  }

  // MARK: Helpers

  private func detachItem() {
    generation = NativePlayer.noSource
    initializedSent = false
    firstFrameSent = false
    awaitingFrame = false
    lastReportedPlaying = false
    rotationDegrees = 0
    pixelAspectRatio = 1
    itemObservations.forEach { $0.invalidate() }
    itemObservations.removeAll()
    itemNotifications.forEach { NotificationCenter.default.removeObserver($0) }
    itemNotifications.removeAll()
    player.pause()
    if let item, let videoOutput { item.remove(videoOutput) }
    if let item, let legibleOutput {
      legibleOutput.setDelegate(nil, queue: nil)
      item.remove(legibleOutput)
    }
    legibleOutput = nil
    player.replaceCurrentItem(with: nil)
    item = nil
    videoOutput = nil
    if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) }
    temporaryFile = nil
    updateDisplayLink()
  }

  private func clearPixelBuffer() {
    pixelBufferLock.lock()
    latestPixelBuffer = nil
    pixelBufferLock.unlock()
  }

  /// Reads rotation and pixel aspect ratio of the first video track.
  /// `AVPlayerItemVideoOutput` delivers frames without the track's
  /// `preferredTransform`, so the rotation is reported to Flutter.
  private func readGeometry(of item: AVPlayerItem) {
    guard
      let track = item.tracks.compactMap({ $0.assetTrack }).first(where: { $0.mediaType == .video })
    else { return }
    let transform = track.preferredTransform
    let degrees = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
    rotationDegrees = Int64(((degrees % 360) + 360) % 360 / 90 * 90)
    if let description = track.formatDescriptions.first {
      let format = description as! CMFormatDescription
      if let par = CMFormatDescriptionGetExtension(
        format, extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio) as? [String: Any],
        let h = (par[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String] as? NSNumber)?.doubleValue,
        let v = (par[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String] as? NSNumber)?.doubleValue,
        h > 0, v > 0
      {
        pixelAspectRatio = h / v
      }
    }
  }

  /// Size of the frames delivered by the video output (before rotation).
  private func frameSize(of item: AVPlayerItem) -> CGSize {
    if let track = item.tracks.compactMap({ $0.assetTrack }).first(where: { $0.mediaType == .video }) {
      let natural = track.naturalSize
      if natural.width > 0, natural.height > 0 { return natural }
    }
    // presentationSize is upright; undo quarter turns to get frame size.
    let presented = item.presentationSize
    return rotationDegrees % 180 == 0
      ? presented : CGSize(width: presented.height, height: presented.width)
  }

  private func emitVideoSize(for item: AVPlayerItem) {
    let presented = item.presentationSize
    guard presented.width > 0, presented.height > 0 else { return }
    let size =
      rotationDegrees % 180 == 0
      ? presented : CGSize(width: presented.height, height: presented.width)
    events.emit(
      PlatformVideoSizeEvent(
        playerId: id, generation: generation, width: Int64(size.width),
        height: Int64(size.height), rotationDegrees: rotationDegrees,
        pixelAspectRatio: pixelAspectRatio))
  }

  private func emitState(_ state: PlatformPlaybackState) {
    guard generation != NativePlayer.noSource else { return }
    events.emit(PlatformStateEvent(playerId: id, generation: generation, state: state))
  }

  private func emitError(_ error: Error?) {
    guard generation != NativePlayer.noSource else { return }
    let nsError = error as NSError?
    events.emit(
      PlatformErrorEvent(
        playerId: id, generation: generation,
        code: error.map(PlaybackErrors.code(for:)) ?? "unknown",
        message: nsError?.localizedDescription ?? "Playback failed.",
        details: nsError.map { "\($0.domain) \($0.code)" }))
  }

  private func milliseconds(_ time: CMTime) -> Int64 {
    guard time.isNumeric else { return 0 }
    return Int64((CMTimeGetSeconds(time) * 1000).rounded())
  }
}

/// Breaks the retain cycle between `CADisplayLink` and its target.
private final class DisplayLinkProxy: NSObject {
  private weak var player: NativePlayer?

  init(_ player: NativePlayer) {
    self.player = player
  }

  @objc func tick() {
    player?.onDisplayLink()
  }
}
