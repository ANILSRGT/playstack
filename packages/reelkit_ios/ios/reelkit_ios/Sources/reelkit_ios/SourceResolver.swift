import AVFoundation
import Foundation

/// Turns a `PlatformSource` into an `AVURLAsset`.
struct SourceResolver {
  /// Resolves a Flutter asset name (and optional package) to its bundle key.
  let assetLookup: (_ name: String, _ package: String?) -> String

  struct Resolved {
    let asset: AVURLAsset
    /// Temporary file owned by this source, deleted when the source is
    /// detached.
    let temporaryFile: URL?
  }

  func resolve(_ source: PlatformSource) throws -> Resolved {
    if source.formatHint == .dash {
      throw PigeonError(
        code: "unsupportedFormat", message: "AVFoundation does not play MPEG-DASH.", details: nil)
    }
    switch source.type {
    case .network:
      guard let string = source.uri, let url = URL(string: string), url.scheme != nil else {
        throw invalid("Invalid network URL: \(source.uri ?? "nil").")
      }
      var options: [String: Any] = [:]
      if !source.httpHeaders.isEmpty {
        // Not declared in the public headers, but the established way to send
        // HTTP headers with AVURLAsset requests (also used by video_player).
        options["AVURLAssetHTTPHeaderFieldsKey"] = source.httpHeaders
      }
      return Resolved(asset: AVURLAsset(url: url, options: options), temporaryFile: nil)
    case .file:
      guard let path = source.uri else { throw invalid("A file source needs a path.") }
      guard FileManager.default.fileExists(atPath: path) else {
        throw PigeonError(code: "sourceNotFound", message: "File not found: \(path)", details: nil)
      }
      return Resolved(asset: AVURLAsset(url: URL(fileURLWithPath: path)), temporaryFile: nil)
    case .asset:
      guard let name = source.assetName else { throw invalid("An asset source needs a name.") }
      let key = assetLookup(name, source.assetPackage)
      guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
        throw PigeonError(
          code: "sourceNotFound", message: "Flutter asset not found: \(name)", details: nil)
      }
      return Resolved(asset: AVURLAsset(url: URL(fileURLWithPath: path)), temporaryFile: nil)
    case .memory:
      guard let bytes = source.bytes else { throw invalid("A memory source needs bytes.") }
      // AVPlayer cannot read from memory directly; the bytes are written to a
      // temporary file that lives as long as the source is attached.
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("reelkit-\(UUID().uuidString)")
        .appendingPathExtension(Self.fileExtension(for: source.mimeType))
      do {
        try bytes.data.write(to: url, options: .atomic)
      } catch {
        throw PigeonError(
          code: "invalidSource", message: "Could not stage memory source: \(error)", details: nil)
      }
      return Resolved(asset: AVURLAsset(url: url), temporaryFile: url)
    }
  }

  private static func fileExtension(for mimeType: String?) -> String {
    switch mimeType?.lowercased() {
    case "video/quicktime": return "mov"
    case "video/x-m4v": return "m4v"
    case "application/x-mpegurl", "application/vnd.apple.mpegurl": return "m3u8"
    default: return "mp4"
    }
  }

  private func invalid(_ message: String) -> PigeonError {
    PigeonError(code: "invalidSource", message: message, details: nil)
  }
}
