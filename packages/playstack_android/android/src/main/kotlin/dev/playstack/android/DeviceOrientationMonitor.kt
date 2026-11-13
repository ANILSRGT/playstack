package dev.playstack.android

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.provider.Settings
import android.view.OrientationEventListener

/**
 * Reports how the user holds the device from the accelerometer, also while
 * the activity is locked to one orientation (the interface does not turn,
 * so Flutter does not see the change). The sensor runs only while Dart
 * listens.
 *
 * Nothing is reported while the user turned auto-rotate off in the system
 * settings.
 */
internal class DeviceOrientationMonitor(private val context: Context) :
    DeviceOrientationEventsStreamHandler() {
  /** The activity, for the orientation the app requested. */
  var activity: Activity? = null

  private var listener: OrientationEventListener? = null
  private var sink: PigeonEventSink<PlatformDeviceOrientationEvent>? = null
  private var last: PlatformOrientation? = null

  override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformDeviceOrientationEvent>) {
    this.sink = sink
    last = null
    if (listener != null) return
    val sensor =
        object : OrientationEventListener(context) {
          override fun onOrientationChanged(degrees: Int) = onDegrees(degrees)
        }
    if (!sensor.canDetectOrientation()) return
    sensor.enable()
    listener = sensor
  }

  override fun onCancel(p0: Any?) = stop()

  fun stop() {
    listener?.disable()
    listener = null
    sink = null
    last = null
  }

  /** The orientations the app requested, as Flutter's SystemChrome sets them. */
  fun appOrientations(): List<PlatformOrientation> {
    val up = PlatformOrientation.PORTRAIT_UP
    val down = PlatformOrientation.PORTRAIT_DOWN
    val left = PlatformOrientation.LANDSCAPE_LEFT
    val right = PlatformOrientation.LANDSCAPE_RIGHT
    return when (activity?.requestedOrientation) {
      ActivityInfo.SCREEN_ORIENTATION_PORTRAIT -> listOf(up)
      ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT -> listOf(down)
      ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT,
      ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT -> listOf(up, down)
      ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE -> listOf(left)
      ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE -> listOf(right)
      ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE,
      ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE -> listOf(left, right)
      ActivityInfo.SCREEN_ORIENTATION_USER -> listOf(up, left, right)
      else -> emptyList()
    }
  }

  private fun onDegrees(degrees: Int) {
    // Lying flat: no orientation.
    if (degrees == OrientationEventListener.ORIENTATION_UNKNOWN) return
    if (!autoRotate()) return
    // Only near an edge, so that holding the device at an angle does not
    // flip between two orientations.
    val orientation =
        when (degrees) {
          in 0..30,
          in 330..359 -> PlatformOrientation.PORTRAIT_UP
          in 60..120 -> PlatformOrientation.LANDSCAPE_RIGHT
          in 150..210 -> PlatformOrientation.PORTRAIT_DOWN
          in 240..300 -> PlatformOrientation.LANDSCAPE_LEFT
          else -> return
        }
    if (orientation == last) return
    last = orientation
    sink?.success(PlatformDeviceOrientationEvent(orientation))
  }

  private fun autoRotate(): Boolean =
      try {
        Settings.System.getInt(context.contentResolver, Settings.System.ACCELEROMETER_ROTATION) ==
            1
      } catch (_: Settings.SettingNotFoundException) {
        true
      }
}
