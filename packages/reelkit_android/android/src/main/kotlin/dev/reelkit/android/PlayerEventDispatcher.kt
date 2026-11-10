package dev.reelkit.android

import android.os.Handler
import android.os.Looper

/**
 * Delivers low-frequency player events to Dart on the platform thread.
 *
 * Events emitted while Dart is not listening are dropped on purpose: the Dart
 * layer re-reads state when it subscribes, and buffering stale events would
 * only waste memory.
 */
internal class PlayerEventDispatcher : PlayerEventsStreamHandler() {
  private val mainHandler = Handler(Looper.getMainLooper())
  private var sink: PigeonEventSink<PlatformPlayerEvent>? = null

  override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformPlayerEvent>) {
    this.sink = sink
  }

  override fun onCancel(p0: Any?) {
    sink = null
  }

  fun emit(event: PlatformPlayerEvent) {
    if (Looper.myLooper() == Looper.getMainLooper()) {
      sink?.success(event)
    } else {
      mainHandler.post { sink?.success(event) }
    }
  }

  fun detach() {
    mainHandler.removeCallbacksAndMessages(null)
    sink = null
  }
}
