import AVFoundation
import Foundation

/// Reads device facts that drive the adaptive player pool size.
///
/// iOS exposes no public API for the number of concurrent hardware decoder
/// sessions, so the recommendation is a memory-based heuristic. Applications
/// can always override it with an explicit pool size.
enum DeviceCapabilities {
  private static let gib: UInt64 = 1024 * 1024 * 1024

  static func read() -> PlatformCapabilities {
    let totalMemory = ProcessInfo.processInfo.physicalMemory
    let recommended: Int64
    switch totalMemory {
    case ..<(3 * gib): recommended = 2
    case ..<(6 * gib): recommended = 3
    default: recommended = 4
    }
    return PlatformCapabilities(
      engineName: "AVFoundation AVPlayer",
      engineVersion: UIDeviceVersion.systemVersion,
      recommendedMaxPlayers: recommended,
      maxHardwareDecoderInstances: nil,
      totalMemoryBytes: Int64(clamping: totalMemory),
      isLowRamDevice: totalMemory < 2 * gib,
      supportsHls: true,
      supportsDash: false,
      supportsDiskCache: false,
      supportsMemorySource: false,
      supportsTrackSelection: false
    )
  }
}

private enum UIDeviceVersion {
  static var systemVersion: String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "iOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
  }
}
