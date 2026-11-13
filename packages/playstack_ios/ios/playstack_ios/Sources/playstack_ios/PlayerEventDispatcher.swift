import Flutter
import Foundation

/// Delivers low-frequency player events to Dart on the main thread.
///
/// Events emitted while Dart is not listening are dropped on purpose: the Dart
/// layer re-reads state when it subscribes.
final class PlayerEventDispatcher: PlayerEventsStreamHandler {
  private var sink: PigeonEventSink<PlatformPlayerEvent>?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<PlatformPlayerEvent>) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func emit(_ event: PlatformPlayerEvent) {
    if Thread.isMainThread {
      sink?.success(event)
    } else {
      DispatchQueue.main.async { [weak self] in self?.sink?.success(event) }
    }
  }

  func detach() {
    sink = nil
  }
}
