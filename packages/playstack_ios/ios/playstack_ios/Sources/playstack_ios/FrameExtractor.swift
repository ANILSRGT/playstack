import AVFoundation
import Flutter
import UIKit

/// Reads still frames for the scrub preview. Keeps the generators of the
/// last few videos: opening one over the network is the slow part.
final class FrameExtractor {
  private let resolver: SourceResolver
  private let queue = DispatchQueue(label: "dev.playstack.frames")
  private var generators: [(key: String, generator: AVAssetImageGenerator)] = []

  init(resolver: SourceResolver) {
    self.resolver = resolver
  }

  func frame(
    source: PlatformSource, positionMs: Int64, maxWidth: Int64,
    completion: @escaping (FlutterStandardTypedData?) -> Void
  ) {
    queue.async { [weak self] in
      guard let self else { return completion(nil) }
      guard let generator = self.generator(for: source) else { return completion(nil) }
      generator.maximumSize = CGSize(width: CGFloat(maxWidth), height: CGFloat(maxWidth) * 4)
      let time = CMTime(value: positionMs, timescale: 1000)
      do {
        let image = try generator.copyCGImage(at: time, actualTime: nil)
        let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
        completion(data.map { FlutterStandardTypedData(bytes: $0) })
      } catch {
        completion(nil)
      }
    }
  }

  private func generator(for source: PlatformSource) -> AVAssetImageGenerator? {
    // Streams have no frames to read without playing them; protected
    // content gives none.
    if source.drm != nil || source.formatHint == .hls || source.formatHint == .dash {
      return nil
    }
    if source.type == .memory { return nil }
    if let uri = source.uri?.lowercased().components(separatedBy: "?").first,
      uri.hasSuffix(".m3u8") || uri.hasSuffix(".mpd")
    {
      return nil
    }
    let key = "\(source.type):\(source.assetPackage ?? "")/\(source.uri ?? source.assetName ?? "")"
    if let index = generators.firstIndex(where: { $0.key == key }) {
      let found = generators.remove(at: index)
      generators.append(found)
      return found.generator
    }
    guard let resolved = try? resolver.resolve(source, cacheEnabled: false) else { return nil }
    let generator = AVAssetImageGenerator(asset: resolved.asset)
    generator.appliesPreferredTrackTransform = true
    // Near is enough for a preview, and much faster than exact.
    let tolerance = CMTime(seconds: 2, preferredTimescale: 600)
    generator.requestedTimeToleranceBefore = tolerance
    generator.requestedTimeToleranceAfter = tolerance
    generators.append((key, generator))
    if generators.count > 3 { generators.removeFirst() }
    return generator
  }
}
