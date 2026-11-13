import AVFoundation
import Foundation

/// Lists and selects tracks of one `AVPlayerItem`.
///
/// Audio and text use AVFoundation media selection groups; ids are
/// `"audio:<n>"` / `"text:<n>"` (index in the group). AVFoundation does not
/// allow choosing a specific video rendition, so the current video track and
/// the stream's renditions (`"variant:<n>"`, HLS only) are listed for
/// information, and video quality is controlled with `preferredPeakBitRate`
/// / `preferredMaximumResolution` instead.
enum TrackSelection {
  static func list(_ item: AVPlayerItem, variants: [AVAssetVariant] = []) -> [PlatformTrack] {
    var tracks: [PlatformTrack] = []
    let selection = item.currentMediaSelection
    for (type, characteristic) in groups {
      guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic)
      else { continue }
      let selected = selection.selectedMediaOption(in: group)
      for (index, option) in group.options.enumerated() {
        // AVFoundation synthesizes "forced only" variants of subtitle
        // options; they are applied automatically and are not a choice for
        // viewers, so they are not listed.
        if option.hasMediaCharacteristic(.containsOnlyForcedSubtitles) { continue }
        tracks.append(
          PlatformTrack(
            id: "\(prefix(type)):\(index)", type: type, isSelected: option == selected,
            label: option.displayName,
            language: option.extendedLanguageTag ?? option.locale?.identifier))
      }
    }
    if let video = item.tracks.compactMap({ $0.assetTrack }).first(where: { $0.mediaType == .video }) {
      let size = video.naturalSize
      tracks.append(
        PlatformTrack(
          id: "video:0", type: .video, isSelected: true, label: nil, language: nil,
          bitrate: video.estimatedDataRate > 0 ? Int64(video.estimatedDataRate) : nil,
          width: size.width > 0 ? Int64(size.width) : nil,
          height: size.height > 0 ? Int64(size.height) : nil,
          frameRate: video.nominalFrameRate > 0 ? Double(video.nominalFrameRate) : nil,
          codecs: codec(of: video)))
    }
    for (index, variant) in variants.enumerated() {
      guard let size = variant.videoAttributes?.presentationSize, size.width > 0, size.height > 0
      else { continue }
      tracks.append(
        PlatformTrack(
          id: "variant:\(index)", type: .video, isSelected: false, label: nil, language: nil,
          bitrate: variant.peakBitRate.map { Int64($0) },
          width: Int64(size.width), height: Int64(size.height),
          frameRate: variant.videoAttributes?.nominalFrameRate))
    }
    return tracks
  }

  static func select(_ item: AVPlayerItem, type: PlatformTrackType, trackId: String?) throws {
    guard type != .video else {
      throw PigeonError(
        code: "notImplemented",
        message: "AVFoundation does not support selecting a video rendition. "
          + "Use setVideoQualityLimit instead.", details: nil)
    }
    let characteristic: AVMediaCharacteristic = type == .audio ? .audible : .legible
    guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else {
      if trackId == nil { return }
      throw unknownTrack(type, trackId)
    }
    guard let trackId else {
      if type == .text {
        item.select(nil, in: group)
      } else {
        item.selectMediaOptionAutomatically(in: group)
      }
      return
    }
    let parts = trackId.split(separator: ":")
    guard parts.count == 2, parts[0] == prefix(type), let index = Int(parts[1]),
      group.options.indices.contains(index)
    else { throw unknownTrack(type, trackId) }
    item.select(group.options[index], in: group)
  }

  static func limitVideo(_ item: AVPlayerItem, maxBitrate: Int64?, maxWidth: Int64?, maxHeight: Int64?) {
    item.preferredPeakBitRate = Double(maxBitrate ?? 0)
    if maxWidth == nil && maxHeight == nil {
      item.preferredMaximumResolution = .zero
    } else {
      item.preferredMaximumResolution = CGSize(
        width: Double(maxWidth ?? Int64(Int32.max)), height: Double(maxHeight ?? Int64(Int32.max)))
    }
  }

  /// FourCC of the track's first format description, for example `avc1`.
  static func codec(of track: AVAssetTrack) -> String? {
    guard let first = track.formatDescriptions.first else { return nil }
    let description = first as! CMFormatDescription
    let code = CMFormatDescriptionGetMediaSubType(description)
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
    return String(bytes: bytes, encoding: .ascii)
  }

  private static let groups: [(PlatformTrackType, AVMediaCharacteristic)] = [
    (.audio, .audible), (.text, .legible),
  ]

  private static func prefix(_ type: PlatformTrackType) -> String {
    switch type {
    case .audio: return "audio"
    case .video: return "video"
    case .text: return "text"
    }
  }

  private static func unknownTrack(_ type: PlatformTrackType, _ id: String?) -> PigeonError {
    PigeonError(
      code: "invalidArgument", message: "Unknown \(prefix(type)) track: \(id ?? "nil")",
      details: nil)
  }
}
