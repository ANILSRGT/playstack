import AVFoundation
import AVKit
import Flutter
import UIKit

/// Shows a player through an `AVPlayerLayer` instead of a Flutter texture.
/// Needed for FairPlay: AVFoundation never hands protected frames to
/// `AVPlayerItemVideoOutput`.
final class PlayerLayerViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "dev.playstack/player_layer"

  private let player: (Int64) -> NativePlayer?

  init(player: @escaping (Int64) -> NativePlayer?) {
    self.player = player
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let id = ((args as? [String: Any])?["playerId"] as? NSNumber)?.int64Value ?? -1
    return PlayerLayerView(frame: frame, player: player(id))
  }
}

final class PlayerLayerView: NSObject, FlutterPlatformView {
  private let container: LayerHostView
  private var observation: NSKeyValueObservation?

  init(frame: CGRect, player: NativePlayer?) {
    container = LayerHostView(frame: frame)
    super.init()
    container.playerLayer.player = player?.avPlayer
    container.playerLayer.videoGravity = .resize
    container.backgroundColor = .black
    observation = container.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
      [weak player] layer, _ in
      guard layer.isReadyForDisplay else { return }
      DispatchQueue.main.async { player?.layerReadyForDisplay() }
    }
  }

  func view() -> UIView { container }

  deinit {
    observation?.invalidate()
    container.playerLayer.player = nil
  }
}

private final class LayerHostView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// The system's AirPlay button (`AVRoutePickerView`).
final class AirPlayButtonFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "dev.playstack/airplay_button"

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let arguments = args as? [String: Any]
    return AirPlayButton(
      frame: frame, tint: (arguments?["color"] as? NSNumber)?.uint32Value,
      activeTint: (arguments?["activeColor"] as? NSNumber)?.uint32Value)
  }
}

final class AirPlayButton: NSObject, FlutterPlatformView {
  private let picker: AVRoutePickerView

  init(frame: CGRect, tint: UInt32?, activeTint: UInt32?) {
    picker = AVRoutePickerView(frame: frame)
    picker.backgroundColor = .clear
    picker.prioritizesVideoDevices = true
    if let tint { picker.tintColor = Self.color(tint) }
    if let activeTint { picker.activeTintColor = Self.color(activeTint) }
    super.init()
  }

  func view() -> UIView { picker }

  private static func color(_ argb: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }
}
