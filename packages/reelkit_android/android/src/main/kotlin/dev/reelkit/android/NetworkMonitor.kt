package dev.reelkit.android

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper

/**
 * Reports connectivity from [ConnectivityManager]. The default-network
 * callback is registered only while Dart listens to network events.
 *
 * Requires `ACCESS_NETWORK_STATE`, declared in this plugin's manifest.
 */
internal class NetworkMonitor(context: Context) : NetworkEventsStreamHandler() {
  private val connectivity =
      context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
  private val mainHandler = Handler(Looper.getMainLooper())
  private var sink: PigeonEventSink<PlatformNetworkStatus>? = null
  private var callback: ConnectivityManager.NetworkCallback? = null
  private var last: PlatformNetworkStatus? = null

  fun current(): PlatformNetworkStatus {
    val network = connectivity.activeNetwork
    return status(network?.let { connectivity.getNetworkCapabilities(it) })
  }

  override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformNetworkStatus>) {
    this.sink = sink
    if (callback != null) return
    val networkCallback =
        object : ConnectivityManager.NetworkCallback() {
          override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
              publish(status(capabilities))

          override fun onLost(network: Network) = publish(current())
        }
    try {
      connectivity.registerDefaultNetworkCallback(networkCallback)
      callback = networkCallback
    } catch (error: RuntimeException) {
      // Too many callbacks registered by the app, or a restricted profile.
      // Dart still has getNetworkStatus().
      sink.error("unknown", "Could not monitor the network: ${error.message}", null)
    }
    publish(current())
  }

  override fun onCancel(p0: Any?) = stop()

  fun stop() {
    callback?.let {
      try {
        connectivity.unregisterNetworkCallback(it)
      } catch (_: RuntimeException) {}
    }
    callback = null
    sink = null
    last = null
    mainHandler.removeCallbacksAndMessages(null)
  }

  private fun publish(status: PlatformNetworkStatus) {
    mainHandler.post {
      if (status == last) return@post
      last = status
      sink?.success(status)
    }
  }

  private fun status(capabilities: NetworkCapabilities?): PlatformNetworkStatus {
    val dataSaver =
        connectivity.restrictBackgroundStatus ==
            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
    if (capabilities == null ||
        !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
      return PlatformNetworkStatus(
          isConnected = false,
          isMetered = false,
          isConstrained = dataSaver,
          type = PlatformNetworkType.NONE,
      )
    }
    val type =
        when {
          capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> PlatformNetworkType.WIFI
          capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ->
              PlatformNetworkType.CELLULAR
          capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ->
              PlatformNetworkType.ETHERNET
          else -> PlatformNetworkType.OTHER
        }
    return PlatformNetworkStatus(
        isConnected = true,
        isMetered = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
        isConstrained = dataSaver,
        type = type,
    )
  }
}
