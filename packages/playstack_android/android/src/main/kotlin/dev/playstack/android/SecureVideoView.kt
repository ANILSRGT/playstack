package dev.playstack.android

import android.content.Context
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Shows a player through a secure [SurfaceView] instead of a Flutter
 * texture. Needed for DRM: protected frames can only reach a secure
 * surface.
 */
internal class SecureVideoViewFactory(private val player: (Long) -> NativePlayer?) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val id = ((args as? Map<*, *>)?.get("playerId") as? Number)?.toLong() ?: -1L
    return SecureVideoView(context, player(id))
  }

  companion object {
    const val VIEW_TYPE = "dev.playstack/secure_video"
  }
}

private class SecureVideoView(context: Context, private val player: NativePlayer?) :
    PlatformView {
  private val surfaceView = SurfaceView(context).apply { setSecure(true) }

  init {
    player?.attachSurfaceView(surfaceView)
  }

  override fun getView(): View = surfaceView

  override fun dispose() {
    player?.detachSurfaceView(surfaceView)
  }
}
