package dev.playstack.android

import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Shows the media notification and keeps playback alive in the background
 * for the video shown in the system's media controls
 * (`PlayStackManager.mediaSession`).
 *
 * Declare it in the app's `AndroidManifest.xml` to enable background
 * playback; see the PlayStack background playback guide.
 */
class PlayStackMediaService : MediaSessionService() {
  override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

  companion object {
    /** The session of the media controls, set by the engine. */
    @Volatile internal var session: MediaSession? = null
  }
}
