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
    /// Cache loader that must live as long as the asset and be closed when
    /// the source is detached.
    var loader: CachingResourceLoader? = nil
  }

  /// With [cacheEnabled], progressive network sources go through the disk
  /// cache.
  func resolve(_ source: PlatformSource, cacheEnabled: Bool) throws -> Resolved {
    if source.formatHint == .dash {
      throw PigeonError(
        code: "unsupportedFormat", message: "AVFoundation does not play MPEG-DASH.", details: nil)
    }
    switch source.type {
    case .network:
      guard let string = source.uri, let url = URL(string: string), url.scheme != nil else {
        throw invalid("Invalid network URL: \(source.uri ?? "nil").")
      }
      if cacheEnabled, source.useCache, Self.isCacheable(source, url: url) {
        let loader = CachingResourceLoader(
          url: url, cacheKey: source.cacheKey ?? string, headers: source.httpHeaders,
          store: .shared)
        return Resolved(asset: loader.makeAsset(), temporaryFile: nil, loader: loader)
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
        .appendingPathComponent("playstack-\(UUID().uuidString)")
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

  /// Progressive HTTP(S) files only: HLS is left to AVFoundation.
  private static func isCacheable(_ source: PlatformSource, url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
      return false
    }
    if source.formatHint == .hls { return false }
    let path = url.path.lowercased()
    if path.hasSuffix(".m3u8") || path.hasSuffix(".m3u") { return false }
    let mime = source.mimeType?.lowercased() ?? ""
    return !mime.contains("mpegurl")
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
