import Flutter
import UIKit

/// Reports how the user holds the device from `UIDevice` orientation
/// notifications, also while the app is locked to one orientation (the
/// interface does not turn, so Flutter does not see the change).
/// Notifications are generated only while Dart listens.
///
/// iOS sends nothing while the user locked rotation in Control Center.
final class DeviceOrientationMonitor: DeviceOrientationEventsStreamHandler {
  private var sink: PigeonEventSink<PlatformDeviceOrientationEvent>?
  private var observer: NSObjectProtocol?
  private var last: PlatformOrientation?

  override func onListen(
    withArguments arguments: Any?, sink: PigeonEventSink<PlatformDeviceOrientationEvent>
  ) {
    self.sink = sink
    last = nil
    guard observer == nil else { return }
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    observer = NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.send(UIDevice.current.orientation)
    }
    send(UIDevice.current.orientation)
  }

  override func onCancel(withArguments arguments: Any?) {
    stop()
  }

  func stop() {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
      UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    observer = nil
    sink = nil
    last = nil
  }

  /// The orientations the app allows right now: the Flutter view
  /// controller's, which follow `SystemChrome.setPreferredOrientations`.
  func appOrientations() -> [PlatformOrientation] {
    guard let root = DeviceOrientationMonitor.rootViewController() else { return [] }
    let mask = root.supportedInterfaceOrientations
    if mask == .all { return [] }
    var orientations: [PlatformOrientation] = []
    if mask.contains(.portrait) { orientations.append(.portraitUp) }
    if mask.contains(.portraitUpsideDown) { orientations.append(.portraitDown) }
    // Flutter maps DeviceOrientation.landscapeLeft to the interface's
    // landscapeLeft.
    if mask.contains(.landscapeLeft) { orientations.append(.landscapeLeft) }
    if mask.contains(.landscapeRight) { orientations.append(.landscapeRight) }
    return orientations
  }

  private func send(_ device: UIDeviceOrientation) {
    let orientation: PlatformOrientation
    switch device {
    case .portrait: orientation = .portraitUp
    case .portraitUpsideDown: orientation = .portraitDown
    // A device turned left shows the interface turned right.
    case .landscapeLeft: orientation = .landscapeRight
    case .landscapeRight: orientation = .landscapeLeft
    default: return  // flat or unknown
    }
    guard let sink, orientation != last else { return }
    last = orientation
    sink.success(PlatformDeviceOrientationEvent(orientation: orientation))
  }

  private static func rootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      for window in scene.windows where window.isKeyWindow {
        if let root = window.rootViewController { return root }
      }
    }
    return scenes.first?.windows.first?.rootViewController
  }
}
