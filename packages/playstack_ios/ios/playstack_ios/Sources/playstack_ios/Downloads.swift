import AVFoundation
import Flutter
import Foundation

/// Sends download changes to Dart.
final class DownloadEvents: DownloadEventsStreamHandler {
  private var sink: PigeonEventSink<PlatformDownload>?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<PlatformDownload>) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func emit(_ download: PlatformDownload) {
    sink?.success(download)
  }

  func detach() {
    sink = nil
  }
}

/// The offline downloads of the app.
///
/// Progressive files are saved with a background `URLSession`, HLS streams
/// with an `AVAssetDownloadURLSession`, so downloads go on while the app is
/// in the background or suspended. An index in Application Support keeps
/// what was saved. Players open the saved file instead of the network while
/// downloads are enabled. All state lives on the main thread.
final class DownloadStore: NSObject {
  static let shared = DownloadStore()

  private static let fileSessionId = "dev.playstack.downloads.files"
  private static let hlsSessionId = "dev.playstack.downloads.hls"

  /// What the index keeps of one download.
  private struct Entry: Codable {
    var id: String
    var key: String
    var url: String
    var title: String?
    var metadata: [String: String]
    var headers: [String: String]
    var isHls: Bool
    var maxVideoHeight: Int?
    var state: Int
    var bytes: Int64
    var total: Int64?
    var percent: Double?
    /// Progressive: relative to the downloads folder. HLS: relative to the
    /// home folder, as Apple asks for `.movpkg` locations.
    var path: String?
    var error: String?
    /// Paused by the app (rather than by turning downloads off).
    var pausedByApp: Bool
  }

  private(set) var enabled = false
  private var entries: [String: Entry] = [:]
  private var order: [String] = []
  private var tasks: [String: URLSessionTask] = [:]
  private var lastProgress: [String: Date] = [:]
  private var listeners: [ObjectIdentifier: (PlatformDownload) -> Void] = [:]
  private var backgroundCompletions: [String: () -> Void] = [:]

  private lazy var folder: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let url = base.appendingPathComponent("playstack_downloads", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var excluded = url
    try? excluded.setResourceValues(values)
    return url
  }()

  private var indexURL: URL { folder.appendingPathComponent("index.json") }

  private lazy var fileSession: URLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: Self.fileSessionId)
    configuration.sessionSendsLaunchEvents = true
    return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
  }()

  private lazy var hlsSession: AVAssetDownloadURLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: Self.hlsSessionId)
    configuration.sessionSendsLaunchEvents = true
    return AVAssetDownloadURLSession(
      configuration: configuration, assetDownloadDelegate: self, delegateQueue: .main)
  }()

  private var loaded = false

  /// Reads the index and reconnects to the tasks of the background
  /// sessions, once.
  private func load() {
    guard !loaded else { return }
    loaded = true
    if let data = try? Data(contentsOf: indexURL),
      let saved = try? JSONDecoder().decode([Entry].self, from: data)
    {
      for entry in saved {
        entries[entry.id] = entry
        order.append(entry.id)
      }
    }
    for session in [fileSession, hlsSession as URLSession] {
      session.getAllTasks { [weak self] found in
        DispatchQueue.main.async {
          guard let self else { return }
          for task in found {
            guard let id = task.taskDescription, self.entries[id] != nil else {
              task.cancel()
              continue
            }
            self.tasks[id] = task
            if !self.enabled { task.suspend() }
          }
        }
      }
    }
  }

  private func save() {
    let list = order.compactMap { entries[$0] }
    if let data = try? JSONEncoder().encode(list) {
      try? data.write(to: indexURL, options: .atomic)
    }
  }

  // MARK: Listeners

  func addListener(_ owner: AnyObject, _ listener: @escaping (PlatformDownload) -> Void) {
    load()
    listeners[ObjectIdentifier(owner)] = listener
  }

  func removeListener(_ owner: AnyObject) {
    listeners.removeValue(forKey: ObjectIdentifier(owner))
  }

  private func notify(_ id: String) {
    guard let entry = entries[id] else { return }
    let download = platform(entry)
    for listener in listeners.values { listener(download) }
  }

  private func notifyRemoved(_ entry: Entry) {
    var download = platform(entry)
    download.state = .removed
    for listener in listeners.values { listener(download) }
  }

  // MARK: Host methods

  func setEnabled(_ value: Bool) {
    load()
    enabled = value
    for (id, task) in tasks {
      guard var entry = entries[id], entry.state != PlatformDownloadState.completed.rawValue else {
        continue
      }
      if value {
        if !entry.pausedByApp {
          task.resume()
          entry.state = PlatformDownloadState.downloading.rawValue
        }
      } else {
        task.suspend()
        entry.state = PlatformDownloadState.paused.rawValue
      }
      entries[id] = entry
      notify(id)
    }
    save()
  }

  func start(_ request: PlatformDownloadRequest) throws {
    load()
    guard enabled else {
      throw PigeonError(code: "notAllowed", message: "Downloads are turned off.", details: nil)
    }
    let source = request.source
    guard source.type == .network, let string = source.uri, let url = URL(string: string),
      url.scheme != nil
    else {
      throw PigeonError(
        code: "invalidSource", message: "Only network sources can be downloaded.", details: nil)
    }
    if source.formatHint == .dash {
      throw PigeonError(
        code: "unsupportedFormat", message: "AVFoundation does not play MPEG-DASH.", details: nil)
    }
    // Starting again replaces what was there.
    if entries[request.id] != nil { discard(request.id) }
    let isHls =
      source.formatHint == .hls || url.pathExtension.lowercased() == "m3u8"
    let entry = Entry(
      id: request.id, key: source.cacheKey ?? string, url: string, title: request.title,
      metadata: request.metadata, headers: source.httpHeaders, isHls: isHls,
      maxVideoHeight: request.maxVideoHeight.map { Int($0) },
      state: PlatformDownloadState.queued.rawValue, bytes: 0, total: nil, percent: nil,
      path: nil, error: nil, pausedByApp: false)
    entries[request.id] = entry
    order.append(request.id)
    startTask(for: entry)
    save()
    notify(request.id)
  }

  private func startTask(for entry: Entry) {
    guard let url = URL(string: entry.url) else { return }
    let task: URLSessionTask
    if entry.isHls {
      var options: [String: Any] = [:]
      if !entry.headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = entry.headers }
      let asset = AVURLAsset(url: url, options: options)
      let configuration = AVAssetDownloadConfiguration(asset: asset, title: entry.title ?? entry.id)
      // A hand-written predicate on the presentation size raises an
      // Objective-C exception; only Apple's own predicates are accepted.
      // Before iOS 16 the best rendition is saved.
      if let maxHeight = entry.maxVideoHeight, #available(iOS 16.0, *) {
        let predicate = AVAssetVariantQualifier.predicate(
          forPresentationHeight: CGFloat(maxHeight), operatorType: .lessThanOrEqualTo)
        configuration.primaryContentConfiguration.variantQualifiers = [
          AVAssetVariantQualifier(predicate: predicate)
        ]
      }
      task = hlsSession.makeAssetDownloadTask(downloadConfiguration: configuration)
    } else {
      var request = URLRequest(url: url)
      for (field, value) in entry.headers { request.setValue(value, forHTTPHeaderField: field) }
      task = fileSession.downloadTask(with: request)
    }
    task.taskDescription = entry.id
    tasks[entry.id] = task
    task.resume()
  }

  func pause(_ id: String) {
    load()
    guard var entry = entries[id], entry.state != PlatformDownloadState.completed.rawValue else {
      return
    }
    entry.pausedByApp = true
    entry.state = PlatformDownloadState.paused.rawValue
    entries[id] = entry
    tasks[id]?.suspend()
    save()
    notify(id)
  }

  func resume(_ id: String) {
    load()
    guard var entry = entries[id], entry.state != PlatformDownloadState.completed.rawValue else {
      return
    }
    entry.pausedByApp = false
    if enabled {
      entry.error = nil
      if let task = tasks[id], task.state == .suspended || task.state == .running {
        task.resume()
        entry.state = PlatformDownloadState.downloading.rawValue
      } else {
        entry.state = PlatformDownloadState.queued.rawValue
        entries[id] = entry
        startTask(for: entry)
      }
    }
    entries[id] = entry
    save()
    notify(id)
  }

  func remove(_ id: String) {
    load()
    guard let entry = entries[id] else { return }
    discard(id)
    save()
    notifyRemoved(entry)
  }

  /// Cancels the task and deletes the files of [id].
  private func discard(_ id: String) {
    tasks.removeValue(forKey: id)?.cancel()
    if let entry = entries.removeValue(forKey: id), let file = fileURL(entry) {
      try? FileManager.default.removeItem(at: file)
    }
    order.removeAll { $0 == id }
    lastProgress.removeValue(forKey: id)
  }

  func all() -> [PlatformDownload] {
    load()
    return order.compactMap { entries[$0] }.map(platform)
  }

  /// The saved file of [key], while downloads are enabled.
  func completedURL(forKey key: String) -> URL? {
    load()
    guard enabled,
      let entry = entries.values.first(where: {
        $0.key == key && $0.state == PlatformDownloadState.completed.rawValue
      }),
      let url = fileURL(entry), FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return url
  }

  /// Keeps the system's completion handler of a background session until
  /// its events are handled.
  func handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) -> Bool {
    guard identifier == Self.fileSessionId || identifier == Self.hlsSessionId else { return false }
    backgroundCompletions[identifier] = completion
    load()
    return true
  }

  // MARK: Helpers

  private func fileURL(_ entry: Entry) -> URL? {
    guard let path = entry.path else { return nil }
    if entry.isHls {
      return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path)
    }
    return folder.appendingPathComponent(path)
  }

  private func platform(_ entry: Entry) -> PlatformDownload {
    PlatformDownload(
      id: entry.id, key: entry.key,
      state: PlatformDownloadState(rawValue: entry.state) ?? .queued,
      bytesDownloaded: entry.bytes, totalBytes: entry.total, percent: entry.percent,
      title: entry.title, metadata: entry.metadata, error: entry.error)
  }

  private func update(_ id: String, force: Bool = false, _ change: (inout Entry) -> Void) {
    guard var entry = entries[id] else { return }
    change(&entry)
    entries[id] = entry
    let now = Date()
    if force || now.timeIntervalSince(lastProgress[id] ?? .distantPast) >= 1 {
      lastProgress[id] = now
      notify(id)
    }
  }

  private static func safeName(_ id: String) -> String {
    String(id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
  }
}

// MARK: Progressive downloads

extension DownloadStore: URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard let id = downloadTask.taskDescription else { return }
    update(id) { entry in
      if entry.state != PlatformDownloadState.paused.rawValue {
        entry.state = PlatformDownloadState.downloading.rawValue
      }
      entry.bytes = totalBytesWritten
      if totalBytesExpectedToWrite > 0 {
        entry.total = totalBytesExpectedToWrite
        entry.percent = Double(totalBytesWritten) * 100 / Double(totalBytesExpectedToWrite)
      }
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let id = downloadTask.taskDescription, let entry = entries[id] else { return }
    if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status >= 400 {
      update(id, force: true) { entry in
        entry.state = PlatformDownloadState.failed.rawValue
        entry.error = "HTTP \(status)"
      }
      return
    }
    let ext = URL(string: entry.url)?.pathExtension
    let name = Self.safeName(id) + "." + (ext?.isEmpty == false ? ext! : "mp4")
    let destination = folder.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: destination)
    do {
      // Must happen before this method returns: the file is deleted after.
      try FileManager.default.moveItem(at: location, to: destination)
      update(id, force: true) { entry in entry.path = name }
    } catch {
      update(id, force: true) { entry in
        entry.state = PlatformDownloadState.failed.rawValue
        entry.error = "Could not save the file: \(error.localizedDescription)"
      }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let id = task.taskDescription, entries[id] != nil else { return }
    if tasks[id] === task { tasks.removeValue(forKey: id) }
    if let error {
      // Cancelled by remove() or a restart.
      if (error as NSError).code == NSURLErrorCancelled { return }
      update(id, force: true) { entry in
        entry.state = PlatformDownloadState.failed.rawValue
        entry.error = error.localizedDescription
      }
    } else if entries[id]?.state != PlatformDownloadState.failed.rawValue {
      update(id, force: true) { entry in
        guard entry.path != nil else {
          entry.state = PlatformDownloadState.failed.rawValue
          entry.error = "The download ended without a file."
          return
        }
        entry.state = PlatformDownloadState.completed.rawValue
        entry.percent = 100
        if let total = entry.total { entry.bytes = total }
      }
    }
    save()
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    guard let identifier = session.configuration.identifier else { return }
    backgroundCompletions.removeValue(forKey: identifier)?()
  }
}

// MARK: HLS downloads

extension DownloadStore: AVAssetDownloadDelegate {
  func urlSession(
    _ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
    willDownloadTo location: URL
  ) {
    guard let id = assetDownloadTask.taskDescription else { return }
    update(id, force: true) { entry in entry.path = location.relativePath }
    save()
  }

  func urlSession(
    _ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let id = assetDownloadTask.taskDescription else { return }
    update(id, force: true) { entry in entry.path = location.relativePath }
    save()
  }

  func urlSession(
    _ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
    totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange
  ) {
    guard let id = assetDownloadTask.taskDescription else { return }
    let expected = timeRangeExpectedToLoad.duration.seconds
    guard expected > 0 else { return }
    let loaded = loadedTimeRanges.map { $0.timeRangeValue.duration.seconds }.reduce(0, +)
    update(id) { entry in
      if entry.state != PlatformDownloadState.paused.rawValue {
        entry.state = PlatformDownloadState.downloading.rawValue
      }
      entry.percent = min(100, loaded * 100 / expected)
      entry.bytes = assetDownloadTask.countOfBytesReceived
    }
  }
}
