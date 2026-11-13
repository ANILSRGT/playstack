package dev.playstack.android

import android.app.Activity
import android.app.Application
import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture

/** Sends media control commands and Picture-in-Picture changes to Dart. */
internal class SystemEvents : SystemEventsStreamHandler() {
  private var sink: PigeonEventSink<PlatformSystemEvent>? = null
  private val mainHandler = Handler(Looper.getMainLooper())

  override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformSystemEvent>) {
    this.sink = sink
  }

  override fun onCancel(p0: Any?) {
    sink = null
  }

  fun emit(type: PlatformSystemEventType, positionMs: Long? = null) {
    val event = PlatformSystemEvent(type, positionMs)
    if (Looper.myLooper() == Looper.getMainLooper()) {
      sink?.success(event)
    } else {
      mainHandler.post { sink?.success(event) }
    }
  }

  fun detach() {
    sink = null
  }
}

/**
 * The player as the media controls see it: the commands of the lock screen,
 * the notification, headphones and cars go to Dart instead of the player,
 * and the metadata comes from the app.
 */
@OptIn(UnstableApi::class)
private class CommandPlayer(
    player: Player,
    private val info: PlatformMediaInfo,
    private val events: SystemEvents,
) : ForwardingPlayer(player) {
  private val metadata =
      MediaMetadata.Builder()
          .setTitle(info.title)
          .setArtist(info.artist)
          .setAlbumTitle(info.album)
          .setArtworkUri(info.artworkUrl?.let { android.net.Uri.parse(it) })
          .build()

  override fun play() = events.emit(PlatformSystemEventType.PLAY)

  override fun pause() = events.emit(PlatformSystemEventType.PAUSE)

  override fun setPlayWhenReady(playWhenReady: Boolean) =
      events.emit(if (playWhenReady) PlatformSystemEventType.PLAY else PlatformSystemEventType.PAUSE)

  override fun seekTo(positionMs: Long) = events.emit(PlatformSystemEventType.SEEK, positionMs)

  override fun seekTo(mediaItemIndex: Int, positionMs: Long) =
      events.emit(PlatformSystemEventType.SEEK, positionMs)

  override fun seekToNext() = next()

  override fun seekToNextMediaItem() = next()

  override fun seekToPrevious() = previous()

  override fun seekToPreviousMediaItem() = previous()

  private fun next() {
    if (info.canSkipNext) events.emit(PlatformSystemEventType.NEXT)
  }

  private fun previous() {
    if (info.canSkipPrevious) {
      events.emit(PlatformSystemEventType.PREVIOUS)
    } else {
      events.emit(PlatformSystemEventType.SEEK, 0)
    }
  }

  override fun getAvailableCommands(): Player.Commands {
    val builder = super.getAvailableCommands().buildUpon()
    for (command in
        listOf(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)) {
      if (info.canSkipNext) builder.add(command) else builder.remove(command)
    }
    for (command in
        listOf(Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)) {
      if (info.canSkipPrevious) builder.add(command) else builder.remove(command)
    }
    builder.add(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)
    return builder.build()
  }

  override fun isCommandAvailable(command: Int): Boolean = availableCommands.contains(command)

  override fun getMediaMetadata(): MediaMetadata = metadata
}

/**
 * A Media3 [MediaSession] for the player shown in the system's media
 * controls. The notification and background playback come from
 * [PlayStackMediaService] when the app declares it in its manifest.
 */
@OptIn(UnstableApi::class)
internal class MediaSessionCoordinator(
    private val context: Context,
    private val events: SystemEvents,
) {
  private var session: MediaSession? = null
  private var player: NativePlayer? = null
  private var controller: ListenableFuture<MediaController>? = null

  fun show(player: NativePlayer?, info: PlatformMediaInfo?) {
    if (player == null || info == null) {
      clear()
      return
    }
    this.player = player
    val forwarding = CommandPlayer(player.exoPlayer, info, events)
    val current = session
    if (current == null) {
      val created = MediaSession.Builder(context, forwarding).setId("playstack").build()
      session = created
      PlayStackMediaService.session = created
      connectService()
    } else {
      current.player = forwarding
    }
  }

  fun clear() {
    controller?.let { MediaController.releaseFuture(it) }
    controller = null
    PlayStackMediaService.session = null
    session?.release()
    session = null
    player = null
  }

  fun playerReleased(released: NativePlayer) {
    if (released === player) clear()
  }

  /** Binds the app's media service, which shows the notification. */
  private fun connectService() {
    val component = ComponentName(context, PlayStackMediaService::class.java)
    val declared =
        try {
          context.packageManager.getServiceInfo(component, 0)
          true
        } catch (_: PackageManager.NameNotFoundException) {
          false
        }
    if (!declared) return
    controller = MediaController.Builder(context, SessionToken(context, component)).buildAsync()
  }
}

/**
 * Picture-in-Picture of the activity. The whole Flutter view is shown in the
 * floating window; Dart shows only the video meanwhile.
 */
internal class PictureInPictureCoordinator(private val events: SystemEvents) :
    Player.Listener, Application.ActivityLifecycleCallbacks {
  private var activity: Activity? = null
  private var player: NativePlayer? = null
  private var autoEnter = false
  private var active = false
  private val layoutListener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> check() }

  fun attach(activity: Activity) {
    detach()
    this.activity = activity
    activity.window?.decorView?.addOnLayoutChangeListener(layoutListener)
    activity.application.registerActivityLifecycleCallbacks(this)
    updateParams()
  }

  fun detach() {
    val current = activity ?: return
    current.window?.decorView?.removeOnLayoutChangeListener(layoutListener)
    current.application.unregisterActivityLifecycleCallbacks(this)
    activity = null
  }

  fun isSupported(): Boolean {
    val current = activity ?: return false
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        current.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
  }

  fun setPlayer(player: NativePlayer?, autoEnter: Boolean) {
    if (player !== this.player) {
      this.player?.exoPlayer?.removeListener(this)
      player?.exoPlayer?.addListener(this)
      this.player = player
    }
    this.autoEnter = autoEnter && player != null
    updateParams()
  }

  fun playerReleased(released: NativePlayer) {
    if (released === player) setPlayer(null, false)
  }

  fun start(): Boolean {
    val current = activity ?: return false
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || player == null) return false
    return try {
      current.enterPictureInPictureMode(params())
    } catch (_: IllegalStateException) {
      false // The activity does not declare android:supportsPictureInPicture.
    } catch (_: IllegalArgumentException) {
      false
    }
  }

  /** Before Android 12, entering on leaving the app is done here. */
  fun onUserLeaveHint() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
    if (autoEnter && player?.exoPlayer?.isPlaying == true) start()
  }

  override fun onIsPlayingChanged(isPlaying: Boolean) = updateParams()

  override fun onVideoSizeChanged(videoSize: VideoSize) = updateParams()

  private fun params(): PictureInPictureParams {
    val builder = PictureInPictureParams.Builder()
    val size = player?.exoPlayer?.videoSize
    if (size != null && size.width > 0 && size.height > 0) {
      // Android accepts ratios between 1:2.39 and 2.39:1.
      val ratio = (size.width * size.pixelWidthHeightRatio) / size.height
      val clamped = ratio.coerceIn(0.42f, 2.38f)
      builder.setAspectRatio(Rational((clamped * 1000).toInt(), 1000))
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      builder.setAutoEnterEnabled(autoEnter && player?.exoPlayer?.isPlaying == true)
      builder.setSeamlessResizeEnabled(false)
    }
    return builder.build()
  }

  private fun updateParams() {
    val current = activity ?: return
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    try {
      current.setPictureInPictureParams(params())
    } catch (_: IllegalStateException) {
      // The activity does not support Picture-in-Picture.
    } catch (_: IllegalArgumentException) {}
  }

  private fun check() {
    val now = activity?.isInPictureInPictureMode == true
    if (now == active) return
    active = now
    events.emit(
        if (now) PlatformSystemEventType.PICTURE_IN_PICTURE_STARTED
        else PlatformSystemEventType.PICTURE_IN_PICTURE_STOPPED)
  }

  override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}

  override fun onActivityStarted(activity: Activity) = check()

  override fun onActivityResumed(activity: Activity) = check()

  override fun onActivityPaused(activity: Activity) = check()

  override fun onActivityStopped(activity: Activity) = check()

  override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

  override fun onActivityDestroyed(activity: Activity) {}
}
