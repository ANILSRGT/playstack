import AVFoundation
import Flutter

/// One `AVPlayer` rendered into one Flutter texture.
///
/// Rendering uses `AVPlayerItemVideoOutput` + `FlutterTexture` rather than an
/// `AVPlayerLayer` platform view: IOSurface-backed pixel buffers are imported
/// by the Flutter engine without a copy, and the video composes with arbitrary
/// Flutter widgets without the overlay and thread-merging costs that platform
/// views add inside scrolling feeds.
final class NativePlayer: NSObject, FlutterTexture {
  let id: Int64
  private(set) var textureId: Int64 = 0
  private let player: AVPlayer
  private var videoOutput: AVPlayerItemVideoOutput?
  private var looping: Bool
  private var playbackSpeed: Float
  private var latestPixelBuffer: CVPixelBuffer?
  private let pixelBufferLock = NSLock()
  private var released = false

  init(id: Int64, options: PlatformPlayerOptions) {
    self.id = id
    player = AVPlayer()
    player.volume = Float(min(max(options.volume, 0), 1))
    // AVPlayer has no persistent loop or rate setting before iOS 16, so both
    // are kept here and applied when an item is attached and played.
    looping = options.looping
    playbackSpeed = Float(options.playbackSpeed)
    super.init()
  }

  func attach(to registry: FlutterTextureRegistry) {
    textureId = registry.register(self)
  }

  // MARK: FlutterTexture

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    pixelBufferLock.lock()
    defer { pixelBufferLock.unlock() }
    guard let buffer = latestPixelBuffer else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  func release(from registry: FlutterTextureRegistry) {
    guard !released else { return }
    released = true
    player.pause()
    player.replaceCurrentItem(with: nil)
    videoOutput = nil
    pixelBufferLock.lock()
    latestPixelBuffer = nil
    pixelBufferLock.unlock()
    registry.unregisterTexture(textureId)
  }
}
