package dev.playstack.android

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadHelper
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.offline.DownloadService
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import java.io.File
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import org.json.JSONObject

/**
 * The offline downloads of the process: a Media3 [DownloadManager] writing
 * into its own cache, which nothing evicts. Players read from that cache
 * while downloads are enabled, so a downloaded source plays without a
 * network.
 */
@OptIn(UnstableApi::class)
internal object DownloadStore {
  private const val DIRECTORY = "playstack_downloads"

  /** The stop reason PlayStack uses for a download the app paused. */
  const val STOP_REASON_PAUSED = 1

  @Volatile private var cache: SimpleCache? = null
  @Volatile private var manager: DownloadManager? = null

  /** Request headers by host, so that downloads send the source's headers. */
  private val headersByHost = ConcurrentHashMap<String, Map<String, String>>()

  /** Completed downloads by key, kept current by [manager]'s listener. */
  private val completedByKey = ConcurrentHashMap<String, Download>()

  /** Whether players may read downloads and downloads may run. */
  @Volatile var enabled = false
    private set

  fun cache(context: Context): Cache =
      cache
          ?: synchronized(this) {
            cache
                ?: SimpleCache(
                        File(context.applicationContext.filesDir, DIRECTORY),
                        NoOpCacheEvictor(),
                        Media3Database.obtain(context),
                    )
                    .also { cache = it }
          }

  fun manager(context: Context): DownloadManager =
      manager
          ?: synchronized(this) {
            manager ?: create(context.applicationContext).also { manager = it }
          }

  private fun create(context: Context): DownloadManager {
    val http =
        DefaultHttpDataSource.Factory()
            .setUserAgent(Util.getUserAgent(context, "PlayStack"))
            .setAllowCrossProtocolRedirects(true)
    val withHeaders =
        ResolvingDataSource.Factory(http) { spec ->
          val headers = spec.uri.host?.let { headersByHost[it] }
          if (headers.isNullOrEmpty()) spec else spec.withAdditionalHeaders(headers)
        }
    val manager =
        DownloadManager(
            context,
            Media3Database.obtain(context),
            cache(context),
            withHeaders,
            Executors.newFixedThreadPool(4),
        )
    manager.maxParallelDownloads = 2
    if (!enabled) manager.pauseDownloads()
    manager.addListener(
        object : DownloadManager.Listener {
          override fun onDownloadChanged(
              manager: DownloadManager,
              download: Download,
              finalException: Exception?,
          ) = remember(download)

          override fun onDownloadRemoved(manager: DownloadManager, download: Download) {
            completedByKey.remove(keyOf(download.request))
          }
        })
    // Downloads saved in earlier runs.
    try {
      manager.downloadIndex.getDownloads().use { cursor ->
        while (cursor.moveToNext()) remember(cursor.download)
      }
    } catch (_: IOException) {}
    return manager
  }

  private fun remember(download: Download) {
    val request = download.request
    val headers = DownloadData.headers(request.data)
    if (headers.isNotEmpty()) request.uri.host?.let { headersByHost[it] = headers }
    val key = keyOf(request)
    if (download.state == Download.STATE_COMPLETED) completedByKey[key] = download
    else completedByKey.remove(key)
  }

  fun setEnabled(context: Context, value: Boolean) {
    enabled = value
    val current = manager ?: if (value) manager(context) else return
    if (value) current.resumeDownloads() else current.pauseDownloads()
  }

  /** The completed download of [key], while downloads are enabled. */
  fun completed(context: Context, key: String): Download? {
    if (!enabled) return null
    // Loads earlier downloads on first use.
    manager(context)
    return completedByKey[key]
  }

  /** The key players look the download up by: the source's cache key or URL. */
  fun keyOf(request: DownloadRequest): String =
      DownloadData.key(request.data) ?: request.customCacheKey ?: request.uri.toString()

  fun rememberHeaders(uri: Uri, headers: Map<String, String>) {
    if (headers.isNotEmpty()) uri.host?.let { headersByHost[it] = headers }
  }

  /** A data source that reads the downloads first, then [upstream]. */
  fun readingFactory(context: Context, upstream: DataSource.Factory): DataSource.Factory =
      CacheDataSource.Factory()
          .setCache(cache(context))
          .setUpstreamDataSourceFactory(upstream)
          // Read only: streaming never adds to the downloads.
          .setCacheWriteDataSinkFactory(null)
}

/** The app's values stored in a [DownloadRequest]'s data. */
internal object DownloadData {
  fun encode(
      key: String,
      title: String?,
      metadata: Map<String, String>,
      headers: Map<String, String>,
  ): ByteArray {
    val json = JSONObject()
    json.put("key", key)
    if (title != null) json.put("title", title)
    json.put("metadata", JSONObject(metadata))
    json.put("headers", JSONObject(headers))
    return json.toString().toByteArray(Charsets.UTF_8)
  }

  private fun json(data: ByteArray): JSONObject? =
      if (data.isEmpty()) null
      else
          try {
            JSONObject(String(data, Charsets.UTF_8))
          } catch (_: org.json.JSONException) {
            null
          }

  fun title(data: ByteArray): String? = json(data)?.optString("title")?.takeIf { it.isNotEmpty() }

  fun key(data: ByteArray): String? = json(data)?.optString("key")?.takeIf { it.isNotEmpty() }

  fun metadata(data: ByteArray): Map<String, String> = map(json(data)?.optJSONObject("metadata"))

  fun headers(data: ByteArray): Map<String, String> = map(json(data)?.optJSONObject("headers"))

  private fun map(json: JSONObject?): Map<String, String> {
    json ?: return emptyMap()
    val result = HashMap<String, String>()
    for (key in json.keys()) result[key] = json.optString(key)
    return result
  }
}

/** Sends download changes to Dart. */
internal class DownloadEvents : DownloadEventsStreamHandler() {
  private var sink: PigeonEventSink<PlatformDownload>? = null

  override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformDownload>) {
    this.sink = sink
  }

  override fun onCancel(p0: Any?) {
    sink = null
  }

  fun emit(download: PlatformDownload) {
    sink?.success(download)
  }

  fun detach() {
    sink = null
  }
}

/**
 * The download host methods of one Flutter engine. Runs on the platform
 * thread, where Media3's download manager calls its listeners.
 */
@OptIn(UnstableApi::class)
internal class DownloadCoordinator(
    private val context: Context,
    private val events: DownloadEvents,
) : DownloadManager.Listener {
  private val handler = Handler(Looper.getMainLooper())
  private var listening: DownloadManager? = null
  private val helpers = HashMap<String, DownloadHelper>()
  private val progress =
      object : Runnable {
        override fun run() {
          val manager = listening ?: return
          val running = manager.currentDownloads.filter { it.state == Download.STATE_DOWNLOADING }
          running.forEach { events.emit(toPlatform(it)) }
          if (running.isNotEmpty()) handler.postDelayed(this, 1000)
        }
      }

  private val serviceClass: Class<out DownloadService>? by lazy {
    val component = ComponentName(context, PlayStackDownloadService::class.java)
    try {
      context.packageManager.getServiceInfo(component, 0)
      PlayStackDownloadService::class.java
    } catch (_: PackageManager.NameNotFoundException) {
      null
    }
  }

  private fun manager(): DownloadManager {
    val manager = DownloadStore.manager(context)
    if (listening !== manager) {
      manager.addListener(this)
      listening = manager
    }
    return manager
  }

  fun setEnabled(enabled: Boolean) {
    DownloadStore.setEnabled(context, enabled)
    if (enabled) manager()
    val service = serviceClass ?: return
    // Keeps the service's manager in step; it is the same instance.
    try {
      if (enabled) DownloadService.sendResumeDownloads(context, service, false)
      else DownloadService.sendPauseDownloads(context, service, false)
    } catch (_: IllegalStateException) {
      // Starting a service from the background is not allowed; the shared
      // manager is already paused or resumed.
    }
  }

  fun start(request: PlatformDownloadRequest) {
    if (!DownloadStore.enabled) {
      throw FlutterError("notAllowed", "Downloads are turned off.", null)
    }
    val source = request.source
    if (source.type != PlatformSourceType.NETWORK) {
      throw FlutterError("invalidSource", "Only network sources can be downloaded.", null)
    }
    val url = source.uri ?: throw FlutterError("invalidSource", "A network source needs a URL.", null)
    val uri = Uri.parse(url)
    DownloadStore.rememberHeaders(uri, source.httpHeaders)
    val key = source.cacheKey ?: url
    val data = DownloadData.encode(key, request.title, request.metadata, source.httpHeaders)
    val adaptive =
        source.formatHint == PlatformVideoFormat.HLS ||
            source.formatHint == PlatformVideoFormat.DASH ||
            Util.inferContentType(uri) != androidx.media3.common.C.CONTENT_TYPE_OTHER
    if (!adaptive) {
      val download =
          DownloadRequest.Builder(request.id, uri)
              .setCustomCacheKey(source.cacheKey)
              .setMimeType(mimeType(source))
              .setData(data)
              .build()
      add(download)
      return
    }
    // Adaptive streams: pick the renditions to save first. Media3 keys
    // their segments itself, so they take no custom cache key; players find
    // the download by the key kept in its data.
    val item = MediaItem.Builder().setUri(uri).setMimeType(mimeType(source)).build()
    helpers.remove(request.id)?.release()
    val parameters =
        DefaultTrackSelector.Parameters.Builder(context)
            .apply { request.maxVideoHeight?.let { setMaxVideoSize(Int.MAX_VALUE, it.toInt()) } }
            .build()
    val http =
        DefaultHttpDataSource.Factory()
            .setUserAgent(Util.getUserAgent(context, "PlayStack"))
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(source.httpHeaders)
    val helper =
        DownloadHelper.Factory()
            .setDataSourceFactory(http)
            .setRenderersFactory(DefaultRenderersFactory(context))
            .setTrackSelectionParameters(parameters)
            .create(item)
    helpers[request.id] = helper
    // Shown as queued until the renditions are known.
    events.emit(
        PlatformDownload(
            id = request.id,
            key = key,
            state = PlatformDownloadState.QUEUED,
            bytesDownloaded = 0,
            title = request.title,
            metadata = request.metadata,
        ))
    helper.prepare(
        object : DownloadHelper.Callback {
          override fun onPrepared(helper: DownloadHelper, tracksInfoAvailable: Boolean) {
            if (helpers.remove(request.id) !== helper) return
            try {
              add(helper.getDownloadRequest(request.id, data))
            } catch (error: RuntimeException) {
              failed(error)
            } finally {
              helper.release()
            }
          }

          override fun onPrepareError(helper: DownloadHelper, e: IOException) {
            if (helpers.remove(request.id) !== helper) return
            helper.release()
            failed(e)
          }

          private fun failed(error: Exception) =
              events.emit(
                  PlatformDownload(
                      id = request.id,
                      key = key,
                      state = PlatformDownloadState.FAILED,
                      bytesDownloaded = 0,
                      title = request.title,
                      metadata = request.metadata,
                      error = error.message ?: error.toString(),
                  ))
        })
  }

  private fun add(request: DownloadRequest) {
    val manager = manager()
    val service = serviceClass
    if (service != null) {
      try {
        DownloadService.sendAddDownload(context, service, request, false)
        return
      } catch (_: IllegalStateException) {
        // The app is in the background: add it to the shared manager.
      }
    }
    manager.addDownload(request)
  }

  fun pause(id: String) = setStopReason(id, DownloadStore.STOP_REASON_PAUSED)

  fun resume(id: String) = setStopReason(id, Download.STOP_REASON_NONE)

  private fun setStopReason(id: String, reason: Int) {
    val manager = manager()
    val service = serviceClass
    if (service != null) {
      try {
        DownloadService.sendSetStopReason(context, service, id, reason, false)
        return
      } catch (_: IllegalStateException) {}
    }
    manager.setStopReason(id, reason)
  }

  fun remove(id: String) {
    helpers.remove(id)?.release()
    val manager = manager()
    val service = serviceClass
    if (service != null) {
      try {
        DownloadService.sendRemoveDownload(context, service, id, false)
        return
      } catch (_: IllegalStateException) {}
    }
    manager.removeDownload(id)
  }

  fun all(): List<PlatformDownload> {
    val result = ArrayList<PlatformDownload>()
    try {
      manager().downloadIndex.getDownloads().use { cursor ->
        while (cursor.moveToNext()) result.add(toPlatform(cursor.download))
      }
    } catch (_: IOException) {}
    return result
  }

  override fun onDownloadChanged(
      manager: DownloadManager,
      download: Download,
      finalException: Exception?,
  ) {
    events.emit(toPlatform(download, finalException))
    if (download.state == Download.STATE_DOWNLOADING) {
      handler.removeCallbacks(progress)
      handler.postDelayed(progress, 1000)
    }
  }

  override fun onDownloadRemoved(manager: DownloadManager, download: Download) {
    events.emit(toPlatform(download).copy(state = PlatformDownloadState.REMOVED))
  }

  override fun onDownloadsPausedChanged(manager: DownloadManager, downloadsPaused: Boolean) {
    all().forEach { events.emit(it) }
  }

  fun detach() {
    handler.removeCallbacks(progress)
    helpers.values.forEach { it.release() }
    helpers.clear()
    listening?.removeListener(this)
    listening = null
  }

  private fun toPlatform(download: Download, error: Exception? = null): PlatformDownload {
    val request = download.request
    val paused = listening?.downloadsPaused == true || !DownloadStore.enabled
    val state =
        when (download.state) {
          Download.STATE_COMPLETED -> PlatformDownloadState.COMPLETED
          Download.STATE_FAILED -> PlatformDownloadState.FAILED
          Download.STATE_STOPPED -> PlatformDownloadState.PAUSED
          Download.STATE_DOWNLOADING ->
              if (paused) PlatformDownloadState.PAUSED else PlatformDownloadState.DOWNLOADING
          else -> if (paused) PlatformDownloadState.PAUSED else PlatformDownloadState.QUEUED
        }
    val percent = download.percentDownloaded
    return PlatformDownload(
        id = request.id,
        key = DownloadStore.keyOf(request),
        state = state,
        bytesDownloaded = download.bytesDownloaded,
        totalBytes = download.contentLength.takeIf { it > 0 },
        percent =
            if (download.state == Download.STATE_COMPLETED) 100.0
            else percent.takeIf { it >= 0 }?.toDouble(),
        title = DownloadData.title(request.data),
        metadata = DownloadData.metadata(request.data),
        error =
            if (download.state == Download.STATE_FAILED)
                error?.message ?: "Download failed (reason ${download.failureReason})."
            else null,
    )
  }

  private fun mimeType(source: PlatformSource): String? =
      when (source.formatHint) {
        PlatformVideoFormat.HLS -> MimeTypes.APPLICATION_M3U8
        PlatformVideoFormat.DASH -> MimeTypes.APPLICATION_MPD
        else -> source.mimeType
      }
}
