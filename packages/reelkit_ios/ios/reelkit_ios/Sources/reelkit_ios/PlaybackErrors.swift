import AVFoundation
import Foundation

/// Maps AVFoundation and networking errors to ReelKit error code names.
enum PlaybackErrors {
  static func code(for error: Error) -> String {
    var current: NSError? = error as NSError
    var fallback = "unknown"
    // AVFoundation wraps the root cause; walk the chain and prefer the most
    // specific match.
    while let nsError = current {
      if let code = specificCode(for: nsError) { return code }
      if nsError.domain == AVFoundationErrorDomain { fallback = avFoundationCode(nsError.code) }
      current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return fallback
  }

  private static func specificCode(for error: NSError) -> String? {
    switch error.domain {
    case NSURLErrorDomain:
      switch error.code {
      case NSURLErrorFileDoesNotExist, NSURLErrorResourceUnavailable: return "sourceNotFound"
      case NSURLErrorTimedOut: return "timeout"
      default: return "network"
      }
    case "CoreMediaErrorDomain":
      switch error.code {
      case -12938, -16845: return "sourceNotFound"  // HTTP 404, HTTP 410
      case -12660, -12661, -12937: return "network"  // HTTP 403, 503, other HTTP failures
      default: return nil
      }
    default:
      return nil
    }
  }

  private static func avFoundationCode(_ code: Int) -> String {
    switch AVError.Code(rawValue: code) {
    case .fileFormatNotRecognized?, .failedToParse?, .formatUnsupported?,
      .contentIsNotAuthorized?, .noCompatibleAlternatesForExternalDisplay?:
      return "unsupportedFormat"
    case .decoderTemporarilyUnavailable?:
      // The decoder exists but no instance could be allocated, typically
      // because other players hold the available decode sessions.
      return "decoderUnavailable"
    case .decoderNotFound?, .decodeFailed?:
      return "decoder"
    case .contentIsUnavailable?, .noLongerPlayable?:
      return "sourceNotFound"
    case .serverIncorrectlyConfigured?, .contentNotUpdated?:
      return "network"
    default:
      return "unknown"
    }
  }
}
