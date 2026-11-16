package dev.playstack.android

import android.app.Notification
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadNotificationHelper
import androidx.media3.exoplayer.offline.DownloadService
import androidx.media3.exoplayer.scheduler.Scheduler

/**
 * Keeps offline downloads running while the app is in the background, with
 * a progress notification.
 *
 * Declare it in the app's `AndroidManifest.xml` to download in the
 * background; see the PlayStack offline viewing guide. Without it,
 * downloads run while the app is open.
 */
@OptIn(UnstableApi::class)
class PlayStackDownloadService :
    DownloadService(
        NOTIFICATION_ID,
        DEFAULT_FOREGROUND_NOTIFICATION_UPDATE_INTERVAL,
        CHANNEL_ID,
        R.string.playstack_download_channel,
        0,
    ) {
  override fun getDownloadManager(): DownloadManager = DownloadStore.manager(this)

  override fun getScheduler(): Scheduler? = null

  override fun getForegroundNotification(
      downloads: MutableList<Download>,
      notMetRequirements: Int,
  ): Notification =
      DownloadNotificationHelper(this, CHANNEL_ID)
          .buildProgressNotification(
              this,
              android.R.drawable.stat_sys_download,
              null,
              downloads.firstNotNullOfOrNull { DownloadData.title(it.request.data) },
              downloads,
              notMetRequirements,
          )

  private companion object {
    const val NOTIFICATION_ID = 0x504c53
    const val CHANNEL_ID = "playstack_downloads"
  }
}
