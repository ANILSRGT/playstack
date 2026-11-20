import Flutter
import GoogleCast
import UIKit

/// Google Cast for PlayStack: device picker, session state and remote
/// playback.
public final class PlayStackCastPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
  GCKSessionManagerListener, GCKRemoteMediaClientListener
{
  private static let receiverKey = "dev.playstack.cast.receiver"

  private var sink: FlutterEventSink?
  private var started = false
  private var timer: Timer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PlayStackCastPlugin()
    let methods = FlutterMethodChannel(
      name: "dev.playstack/cast", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(
      name: "dev.playstack/cast/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  /// Starts the Cast context on first use, with the receiver set from
  /// Dart or the default media receiver.
  private func start() {
    guard !started else { return }
    started = true
    let receiver =
      UserDefaults.standard.string(forKey: Self.receiverKey)
      ?? kGCKDefaultMediaReceiverApplicationID
    let options = GCKCastOptions(
      discoveryCriteria: GCKDiscoveryCriteria(applicationID: receiver))
    options.physicalVolumeButtonsWillControlDeviceVolume = true
    GCKCastContext.setSharedInstanceWith(options)
    GCKCastContext.sharedInstance().sessionManager.add(self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(castStateChanged), name: .gckCastStateDidChange, object: nil)
    if let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession {
      attach(session)
    }
  }

  private var client: GCKRemoteMediaClient? {
    GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setReceiverApplicationId":
      UserDefaults.standard.set(call.arguments as? String, forKey: Self.receiverKey)
      result(nil)
      return
    default:
      break
    }
    start()
    switch call.method {
    case "getState":
      result(stateName())
    case "showDevicePicker":
      GCKCastContext.sharedInstance().presentCastDialog()
      result(nil)
    case "load":
      guard let client, let arguments = call.arguments as? [String: Any],
        let url = (arguments["url"] as? String).flatMap(URL.init(string:))
      else {
        result(FlutterError(code: "notAllowed", message: "No Cast device is connected.", details: nil))
        return
      }
      let metadata = GCKMediaMetadata(metadataType: .movie)
      if let title = arguments["title"] as? String {
        metadata.setString(title, forKey: kGCKMetadataKeyTitle)
      }
      if let subtitle = arguments["subtitle"] as? String {
        metadata.setString(subtitle, forKey: kGCKMetadataKeySubtitle)
      }
      if let artwork = (arguments["artworkUrl"] as? String).flatMap(URL.init(string:)) {
        metadata.addImage(GCKImage(url: artwork, width: 480, height: 270))
      }
      let builder = GCKMediaInformationBuilder(contentURL: url)
      builder.streamType = .buffered
      builder.contentType = arguments["contentType"] as? String ?? "video/mp4"
      builder.metadata = metadata
      let options = GCKMediaLoadOptions()
      options.autoplay = arguments["autoplay"] as? Bool ?? true
      options.playPosition = Double((arguments["positionMs"] as? NSNumber)?.int64Value ?? 0) / 1000
      client.loadMedia(builder.build(), with: options)
      result(nil)
    case "play":
      client?.play()
      result(nil)
    case "pause":
      client?.pause()
      result(nil)
    case "seekTo":
      let options = GCKMediaSeekOptions()
      options.interval = Double((call.arguments as? NSNumber)?.int64Value ?? 0) / 1000
      client?.seek(with: options)
      result(nil)
    case "setVolume":
      client?.setStreamVolume(Float((call.arguments as? NSNumber)?.doubleValue ?? 1))
      result(nil)
    case "stop":
      client?.stop()
      result(nil)
    case "disconnect":
      GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Events

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    start()
    sendState()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  @objc private func castStateChanged() { sendState() }

  private func stateName() -> String {
    guard started else { return "unavailable" }
    switch GCKCastContext.sharedInstance().castState {
    case .noDevicesAvailable: return "noDevices"
    case .notConnected: return "notConnected"
    case .connecting: return "connecting"
    case .connected: return "connected"
    @unknown default: return "unavailable"
    }
  }

  private func sendState() {
    let device =
      started
      ? GCKCastContext.sharedInstance().sessionManager.currentCastSession?.device.friendlyName
      : nil
    sink?(["type": "state", "state": stateName(), "device": device as Any])
  }

  private func sendPlayback() {
    guard let client else { return }
    let status = client.mediaStatus
    let duration = status?.mediaInformation?.streamDuration ?? 0
    sink?([
      "type": "playback",
      "playing": status?.playerState == .playing,
      "buffering": status?.playerState == .buffering || status?.playerState == .loading,
      "positionMs": Int64(client.approximateStreamPosition() * 1000),
      "durationMs": duration.isFinite ? Int64(duration * 1000) : -1,
      "hasMedia": status?.mediaInformation != nil,
    ])
  }

  private func attach(_ session: GCKCastSession) {
    session.remoteMediaClient?.add(self)
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.sendPlayback()
    }
    sendState()
  }

  private func detach() {
    timer?.invalidate()
    timer = nil
    sendState()
  }

  // MARK: GCKSessionManagerListener

  public func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
    attach(session)
  }

  public func sessionManager(
    _ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession
  ) {
    attach(session)
  }

  public func sessionManager(
    _ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?
  ) {
    detach()
  }

  public func sessionManager(
    _ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error
  ) {
    sendState()
  }

  // MARK: GCKRemoteMediaClientListener

  public func remoteMediaClient(
    _ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?
  ) {
    sendPlayback()
  }
}
