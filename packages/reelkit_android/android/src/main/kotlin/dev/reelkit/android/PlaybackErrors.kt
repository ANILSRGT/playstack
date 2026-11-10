package dev.reelkit.android

import androidx.annotation.OptIn
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource

/** Maps Media3 errors to ReelKit error code names. */
internal object PlaybackErrors {
  @OptIn(UnstableApi::class)
  fun code(error: PlaybackException): String =
      when (error.errorCode) {
        PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND -> "sourceNotFound"
        PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS -> {
          val status = (error.cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode
          if (status == 404 || status == 410) "sourceNotFound" else "network"
        }
        PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
        PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
        PlaybackException.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE,
        PlaybackException.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED,
        PlaybackException.ERROR_CODE_IO_UNSPECIFIED -> "network"
        PlaybackException.ERROR_CODE_TIMEOUT -> "timeout"
        PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
        PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES -> "unsupportedFormat"
        in PARSING_RANGE -> "unsupportedFormat"
        in DECODING_RANGE -> "decoder"
        else -> "unknown"
      }

  private val PARSING_RANGE = 3000..3999
  private val DECODING_RANGE = 4000..4999
}
