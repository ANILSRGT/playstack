package dev.playstack.cast

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.appcompat.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteControllerDialog
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.CastState
import com.google.android.gms.cast.framework.CastStateListener
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.images.WebImage
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Google Cast for PlayStack: device picker, session state and remote playback. */
class PlayStackCastPlugin :
    FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
  private lateinit var context: Context
  private var methods: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var sink: EventChannel.EventSink? = null
  private var activity: Activity? = null
  private var cast: CastContext? = null
  private val main = Handler(Looper.getMainLooper())

  private val stateListener = CastStateListener { sendState() }

  private val sessions =
      object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) = attach(session)

        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) =
            attach(session)

        override fun onSessionEnded(session: CastSession, error: Int) = detach()

        override fun onSessionStarting(session: CastSession) = sendState()

        override fun onSessionStartFailed(session: CastSession, error: Int) = sendState()

        override fun onSessionEnding(session: CastSession) {}

        override fun onSessionResuming(session: CastSession, sessionId: String) {}

        override fun onSessionResumeFailed(session: CastSession, error: Int) = sendState()

        override fun onSessionSuspended(session: CastSession, reason: Int) = sendState()
      }

  private var client: RemoteMediaClient? = null
  private val progress =
      RemoteMediaClient.ProgressListener { _, _ -> sendPlayback() }
  private val clientCallback =
      object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() = sendPlayback()
      }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    methods =
        MethodChannel(binding.binaryMessenger, "dev.playstack/cast").also {
          it.setMethodCallHandler(this)
        }
    eventChannel =
        EventChannel(binding.binaryMessenger, "dev.playstack/cast/events").also {
          it.setStreamHandler(this)
        }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods?.setMethodCallHandler(null)
    eventChannel?.setStreamHandler(null)
    cast?.removeCastStateListener(stateListener)
    cast?.sessionManager?.removeSessionManagerListener(sessions, CastSession::class.java)
    detach()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  /** Starts Cast on first use; null without Google Play services. */
  private fun castContext(): CastContext? {
    cast?.let { return it }
    return try {
      CastContext.getSharedInstance(context).also {
        cast = it
        it.addCastStateListener(stateListener)
        it.sessionManager.addSessionManagerListener(sessions, CastSession::class.java)
        it.sessionManager.currentCastSession?.let(::attach)
      }
    } catch (error: Exception) {
      null
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    try {
      when (call.method) {
        "setReceiverApplicationId" -> {
          context
              .getSharedPreferences(CastOptionsProvider.PREFERENCES, Context.MODE_PRIVATE)
              .edit()
              .putString(CastOptionsProvider.RECEIVER_KEY, call.arguments as String)
              .apply()
          result.success(null)
        }
        "getState" -> result.success(stateName())
        "showDevicePicker" -> {
          showPicker()
          result.success(null)
        }
        "load" -> {
          load(call.arguments as Map<*, *>)
          result.success(null)
        }
        "play" -> {
          client?.play()
          result.success(null)
        }
        "pause" -> {
          client?.pause()
          result.success(null)
        }
        "seekTo" -> {
          val position = (call.arguments as Number).toLong()
          client?.seek(MediaSeekOptions.Builder().setPosition(position).build())
          result.success(null)
        }
        "setVolume" -> {
          client?.setStreamVolume((call.arguments as Number).toDouble())
          result.success(null)
        }
        "stop" -> {
          client?.stop()
          result.success(null)
        }
        "disconnect" -> {
          castContext()?.sessionManager?.endCurrentSession(true)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    } catch (error: Exception) {
      result.error("unknown", error.message, null)
    }
  }

  private fun showPicker() {
    val cast = castContext() ?: throw IllegalStateException("Cast is not available.")
    val current = activity ?: throw IllegalStateException("No activity.")
    // The router dialogs need an AppCompat theme; Flutter activities have
    // none.
    val themed = ContextThemeWrapper(current, androidx.appcompat.R.style.Theme_AppCompat_NoActionBar)
    if (cast.sessionManager.currentCastSession?.isConnected == true) {
      MediaRouteControllerDialog(themed).show()
    } else {
      MediaRouteChooserDialog(themed).apply { routeSelector = cast.mergedSelector!! }.show()
    }
  }

  private fun load(arguments: Map<*, *>) {
    val client = client ?: throw IllegalStateException("No Cast device is connected.")
    val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE)
    (arguments["title"] as String?)?.let { metadata.putString(MediaMetadata.KEY_TITLE, it) }
    (arguments["subtitle"] as String?)?.let {
      metadata.putString(MediaMetadata.KEY_SUBTITLE, it)
    }
    (arguments["artworkUrl"] as String?)?.let { metadata.addImage(WebImage(Uri.parse(it))) }
    val media =
        MediaInfo.Builder(arguments["url"] as String)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType(arguments["contentType"] as String)
            .setMetadata(metadata)
            .build()
    client.load(
        MediaLoadRequestData.Builder()
            .setMediaInfo(media)
            .setAutoplay(arguments["autoplay"] as Boolean? ?: true)
            .setCurrentTime((arguments["positionMs"] as Number?)?.toLong() ?: 0L)
            .build())
  }

  private fun attach(session: CastSession) {
    detachClient()
    client =
        session.remoteMediaClient?.also {
          it.registerCallback(clientCallback)
          it.addProgressListener(progress, 1000)
        }
    sendState()
    sendPlayback()
  }

  private fun detach() {
    detachClient()
    sendState()
  }

  private fun detachClient() {
    client?.unregisterCallback(clientCallback)
    client?.removeProgressListener(progress)
    client = null
  }

  private fun stateName(): String {
    val cast = castContext() ?: return "unavailable"
    return when (cast.castState) {
      CastState.NO_DEVICES_AVAILABLE -> "noDevices"
      CastState.NOT_CONNECTED -> "notConnected"
      CastState.CONNECTING -> "connecting"
      CastState.CONNECTED -> "connected"
      else -> "unavailable"
    }
  }

  private fun sendState() {
    val device = cast?.sessionManager?.currentCastSession?.castDevice?.friendlyName
    send(mapOf("type" to "state", "state" to stateName(), "device" to device))
  }

  private fun sendPlayback() {
    val client = client ?: return
    val status = client.mediaStatus
    send(
        mapOf(
            "type" to "playback",
            "playing" to (status?.playerState == MediaStatus.PLAYER_STATE_PLAYING),
            "buffering" to (status?.playerState == MediaStatus.PLAYER_STATE_BUFFERING),
            "positionMs" to client.approximateStreamPosition,
            "durationMs" to client.streamDuration,
            "hasMedia" to client.hasMediaSession(),
        ))
  }

  private fun send(event: Map<String, Any?>) = main.post { sink?.success(event) }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
    sink = events
    castContext()
    sendState()
  }

  override fun onCancel(arguments: Any?) {
    sink = null
  }
}
