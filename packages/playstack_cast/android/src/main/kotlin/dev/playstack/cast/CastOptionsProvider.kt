package dev.playstack.cast

import android.content.Context
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions
import com.google.android.gms.cast.framework.media.NotificationOptions

/** Cast options: the receiver app set from Dart, or the default media receiver. */
class CastOptionsProvider : OptionsProvider {
  override fun getCastOptions(context: Context): CastOptions {
    val receiver =
        context
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString(RECEIVER_KEY, null)
            ?: CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID
    return CastOptions.Builder()
        .setReceiverApplicationId(receiver)
        .setCastMediaOptions(
            CastMediaOptions.Builder()
                .setNotificationOptions(NotificationOptions.Builder().build())
                .build())
        .build()
  }

  override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null

  companion object {
    const val PREFERENCES = "dev.playstack.cast"
    const val RECEIVER_KEY = "receiver"
  }
}
