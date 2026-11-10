import Flutter
import Foundation
import Network

/// Reports connectivity from `NWPathMonitor`.
///
/// A monitor runs for the plugin's lifetime so that `getNetworkStatus` can
/// answer synchronously; it is cheap (no polling). Changes are forwarded to
/// Dart only while the network event stream has a listener.
final class NetworkMonitor: NetworkEventsStreamHandler {
  private let monitor = NWPathMonitor()
  private var sink: PigeonEventSink<PlatformNetworkStatus>?
  private var latest: PlatformNetworkStatus?
  private var lastSent: PlatformNetworkStatus?

  override init() {
    super.init()
    monitor.pathUpdateHandler = { [weak self] path in
      let status = NetworkMonitor.status(of: path)
      DispatchQueue.main.async { self?.update(status) }
    }
    monitor.start(queue: DispatchQueue(label: "dev.reelkit.network"))
  }

  /// The latest known status. Before the first path update (shortly after
  /// start) the type is `unknown` and the connection is assumed available.
  func current() -> PlatformNetworkStatus {
    latest
      ?? PlatformNetworkStatus(
        isConnected: true, isMetered: false, isConstrained: false, type: .unknown)
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<PlatformNetworkStatus>) {
    self.sink = sink
    lastSent = nil
    if let latest { send(latest) }
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func stop() {
    sink = nil
    monitor.cancel()
  }

  private func update(_ status: PlatformNetworkStatus) {
    latest = status
    send(status)
  }

  private func send(_ status: PlatformNetworkStatus) {
    guard let sink, !NetworkMonitor.same(status, lastSent) else { return }
    lastSent = status
    sink.success(status)
  }

  private static func same(_ a: PlatformNetworkStatus, _ b: PlatformNetworkStatus?) -> Bool {
    guard let b else { return false }
    return a.isConnected == b.isConnected && a.isMetered == b.isMetered
      && a.isConstrained == b.isConstrained && a.type == b.type
  }

  private static func status(of path: NWPath) -> PlatformNetworkStatus {
    guard path.status == .satisfied else {
      return PlatformNetworkStatus(
        isConnected: false, isMetered: false, isConstrained: path.isConstrained, type: .none)
    }
    let type: PlatformNetworkType
    if path.usesInterfaceType(.wifi) {
      type = .wifi
    } else if path.usesInterfaceType(.cellular) {
      type = .cellular
    } else if path.usesInterfaceType(.wiredEthernet) {
      type = .ethernet
    } else {
      type = .other
    }
    return PlatformNetworkStatus(
      isConnected: true, isMetered: path.isExpensive, isConstrained: path.isConstrained,
      type: type)
  }
}
