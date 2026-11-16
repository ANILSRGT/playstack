package dev.playstack.android

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider

/** One Media3 database for the disk cache and the downloads of the process. */
@OptIn(UnstableApi::class)
internal object Media3Database {
  @Volatile private var provider: StandaloneDatabaseProvider? = null

  fun obtain(context: Context): StandaloneDatabaseProvider =
      provider
          ?: synchronized(this) {
            provider ?: StandaloneDatabaseProvider(context.applicationContext).also { provider = it }
          }
}
