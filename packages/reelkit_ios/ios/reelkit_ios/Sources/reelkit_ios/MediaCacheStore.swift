import CryptoKit
import Foundation

/// Process-wide disk cache of progressive network videos.
///
/// Each cached resource is a sparse data file plus the byte ranges known to
/// be valid in it, so partially watched videos are cached as far as they
/// were downloaded and seeks fill gaps. Metadata is kept in one index file.
/// Resources are evicted least recently used first once the total exceeds
/// the size limit; resources being read are never evicted.
///
/// All state is confined to a serial queue; every public method is safe to
/// call from any thread.
final class MediaCacheStore {
  static let shared = MediaCacheStore()

  struct Entry: Codable {
    var key: String
    var contentLength: Int64?
    var contentType: String?
    /// Sorted, non-overlapping half-open ranges `[start, end)`.
    var ranges: [[Int64]]
    var lastAccess: Date

    var cachedBytes: Int64 { ranges.reduce(0) { $0 + ($1[1] - $1[0]) } }
  }

  private let queue = DispatchQueue(label: "dev.reelkit.cache.store")
  private let directory: URL
  private var entries: [String: Entry] = [:]
  private var inUse: [String: Int] = [:]
  private var loaded = false
  private var configured = false
  private var maxBytes: Int64 = 0
  private var indexDirty = false

  private init() {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    directory = caches.appendingPathComponent("reelkit_media_cache", isDirectory: true)
  }

  /// Sets the size limit. The first call wins, like the Android cache.
  func configure(maxBytes: Int64) {
    queue.sync {
      guard !configured else { return }
      configured = true
      self.maxBytes = maxBytes
    }
  }

  var isConfigured: Bool { queue.sync { configured && maxBytes > 0 } }

  var limit: Int64 { queue.sync { maxBytes } }

  // MARK: Reading and writing

  /// Marks [key] as being read so it is not evicted.
  func retain(_ key: String) {
    queue.sync {
      loadIfNeeded()
      inUse[key, default: 0] += 1
      touch(key)
    }
  }

  func release(_ key: String) {
    queue.sync {
      if let count = inUse[key] {
        inUse[key] = count > 1 ? count - 1 : nil
      }
      evictIfNeeded()
      saveIndexIfNeeded()
    }
  }

  func info(_ key: String) -> (length: Int64?, type: String?) {
    queue.sync {
      loadIfNeeded()
      let entry = entries[key]
      return (entry?.contentLength, entry?.contentType)
    }
  }

  func setInfo(_ key: String, length: Int64?, type: String?) {
    queue.sync {
      loadIfNeeded()
      var entry = entries[key] ?? Entry(key: key, ranges: [], lastAccess: Date())
      if let length, entry.contentLength != length {
        if entry.contentLength != nil {
          // The resource changed size: the cached bytes are stale.
          entry.ranges = []
          try? FileManager.default.removeItem(at: dataURL(for: key))
        }
        entry.contentLength = length
      }
      if let type { entry.contentType = type }
      entry.lastAccess = Date()
      entries[key] = entry
      indexDirty = true
    }
  }

  /// Number of bytes cached contiguously from [offset].
  func contiguousBytes(_ key: String, from offset: Int64) -> Int64 {
    queue.sync {
      guard let ranges = entries[key]?.ranges else { return 0 }
      for range in ranges where range[0] <= offset && offset < range[1] {
        return range[1] - offset
      }
      return 0
    }
  }

  func read(_ key: String, offset: Int64, length: Int) -> Data? {
    queue.sync {
      guard let handle = try? FileHandle(forReadingFrom: dataURL(for: key)) else { return nil }
      defer { try? handle.close() }
      do {
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: length)
      } catch {
        return nil
      }
    }
  }

  func write(_ key: String, offset: Int64, data: Data) {
    guard !data.isEmpty else { return }
    queue.sync {
      loadIfNeeded()
      let url = dataURL(for: key)
      let manager = FileManager.default
      do {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
          manager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: data)
      } catch {
        return  // Disk full or unwritable: playback continues uncached.
      }
      var entry = entries[key] ?? Entry(key: key, ranges: [], lastAccess: Date())
      entry.ranges = Self.merge(entry.ranges, [offset, offset + Int64(data.count)])
      entry.lastAccess = Date()
      entries[key] = entry
      indexDirty = true
    }
  }

  // MARK: Inspection

  func usedBytes() -> Int64 {
    queue.sync {
      loadIfNeeded()
      return entries.values.reduce(0) { $0 + $1.cachedBytes }
    }
  }

  func cachedBytes(_ key: String) -> Int64 {
    queue.sync {
      loadIfNeeded()
      return entries[key]?.cachedBytes ?? 0
    }
  }

  func remove(_ key: String) {
    queue.sync {
      loadIfNeeded()
      guard inUse[key] == nil else { return }
      deleteEntry(key)
      saveIndexIfNeeded()
    }
  }

  func clear() {
    queue.sync {
      loadIfNeeded()
      for key in Array(entries.keys) where inUse[key] == nil {
        deleteEntry(key)
      }
      saveIndexIfNeeded()
    }
  }

  // MARK: Internals (on queue)

  private func touch(_ key: String) {
    guard var entry = entries[key] else { return }
    entry.lastAccess = Date()
    entries[key] = entry
    indexDirty = true
  }

  private func evictIfNeeded() {
    guard maxBytes > 0 else { return }
    var total = entries.values.reduce(0) { $0 + $1.cachedBytes }
    guard total > maxBytes else { return }
    let candidates = entries.values
      .filter { inUse[$0.key] == nil }
      .sorted { $0.lastAccess < $1.lastAccess }
    for entry in candidates where total > maxBytes {
      total -= entry.cachedBytes
      deleteEntry(entry.key)
    }
  }

  private func deleteEntry(_ key: String) {
    entries.removeValue(forKey: key)
    try? FileManager.default.removeItem(at: dataURL(for: key))
    indexDirty = true
  }

  private var indexURL: URL { directory.appendingPathComponent("index.json") }

  private func dataURL(for key: String) -> URL {
    let digest = SHA256.hash(data: Data(key.utf8))
    let name = digest.map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(name).appendingPathExtension("data")
  }

  private func loadIfNeeded() {
    guard !loaded else { return }
    loaded = true
    guard let data = try? Data(contentsOf: indexURL),
      let decoded = try? JSONDecoder().decode([Entry].self, from: data)
    else { return }
    for entry in decoded {
      entries[entry.key] = entry
    }
  }

  private func saveIndexIfNeeded() {
    guard indexDirty else { return }
    indexDirty = false
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(Array(entries.values))
      try data.write(to: indexURL, options: .atomic)
    } catch {
      // The cache is an optimization; losing the index only loses hits.
    }
  }

  static func merge(_ ranges: [[Int64]], _ new: [Int64]) -> [[Int64]] {
    var result: [[Int64]] = []
    var current = new
    for range in ranges {
      if range[1] < current[0] || range[0] > current[1] {
        result.append(range)
      } else {
        current = [min(range[0], current[0]), max(range[1], current[1])]
      }
    }
    result.append(current)
    return result.sorted { $0[0] < $1[0] }
  }
}
