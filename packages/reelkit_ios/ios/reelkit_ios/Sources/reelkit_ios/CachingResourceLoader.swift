import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Serves an `AVURLAsset` through `AVAssetResourceLoader`, answering byte
/// ranges from `MediaCacheStore` and downloading (and storing) the rest.
///
/// AVFoundation only consults a resource loader for URL schemes it does not
/// handle itself, so the asset URL's scheme is rewritten (`https` becomes
/// `reelkit-cache-https`) and restored for the real request. Used for
/// progressive files only; HLS manifests and segments are not cached on iOS.
///
/// The asset's resource loader holds its delegate weakly; the owner keeps
/// this object alive as long as the asset is in use.
final class CachingResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate
{
  static let schemePrefix = "reelkit-cache-"

  let cacheKey: String
  private let originalURL: URL
  private let headers: [String: String]
  private let store: MediaCacheStore
  private let queue = DispatchQueue(label: "dev.reelkit.cache.loader")
  private var session: URLSession!
  private var tasks: [Int: LoadingTask] = [:]
  private var pending: [LoadingTask] = []
  private var closed = false

  init(url: URL, cacheKey: String, headers: [String: String], store: MediaCacheStore) {
    originalURL = url
    self.cacheKey = cacheKey
    self.headers = headers
    self.store = store
    super.init()
    let operations = OperationQueue()
    operations.maxConcurrentOperationCount = 1
    operations.underlyingQueue = queue
    session = URLSession(
      configuration: .default, delegate: self, delegateQueue: operations)
    store.retain(cacheKey)
  }

  /// The asset to play: same URL with the private scheme.
  func makeAsset() -> AVURLAsset {
    var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)!
    components.scheme = Self.schemePrefix + (originalURL.scheme ?? "https")
    let asset = AVURLAsset(url: components.url!)
    asset.resourceLoader.setDelegate(self, queue: queue)
    return asset
  }

  /// Cancels downloads and lets the cache evict this resource again.
  func close() {
    queue.async {
      guard !self.closed else { return }
      self.closed = true
      self.session.invalidateAndCancel()
      for task in self.pending { task.cancel() }
      self.pending.removeAll()
      self.tasks.removeAll()
      self.store.release(self.cacheKey)
    }
  }

  // MARK: AVAssetResourceLoaderDelegate

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard !closed else { return false }
    let task = LoadingTask(request: loadingRequest, owner: self)
    pending.append(task)
    task.start()
    return true
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    for task in pending where task.request === loadingRequest {
      task.cancel()
    }
    pending.removeAll { $0.request === loadingRequest }
  }

  // MARK: URLSessionDataDelegate (on queue)

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let task = tasks[dataTask.taskIdentifier] else {
      completionHandler(.cancel)
      return
    }
    completionHandler(task.didReceive(response) ? .allow : .cancel)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    tasks[dataTask.taskIdentifier]?.didReceive(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let loading = tasks.removeValue(forKey: task.taskIdentifier) else { return }
    loading.didComplete(error)
  }

  // MARK: Used by LoadingTask (on queue)

  fileprivate func startDownload(for task: LoadingTask, from offset: Int64, to end: Int64?)
    -> URLSessionDataTask
  {
    var request = URLRequest(url: originalURL)
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    let range = end.map { "bytes=\(offset)-\($0 - 1)" } ?? "bytes=\(offset)-"
    request.setValue(range, forHTTPHeaderField: "Range")
    let dataTask = session.dataTask(with: request)
    tasks[dataTask.taskIdentifier] = task
    dataTask.resume()
    return dataTask
  }

  fileprivate func finished(_ task: LoadingTask) {
    pending.removeAll { $0 === task }
  }

  fileprivate var cache: MediaCacheStore { store }
}

/// One `AVAssetResourceLoadingRequest`: content information and/or a byte
/// range, answered from the cache first, then from the network.
private final class LoadingTask {
  let request: AVAssetResourceLoadingRequest
  private unowned let owner: CachingResourceLoader
  private var offset: Int64 = 0
  private var end: Int64?
  private var download: URLSessionDataTask?
  private var skip: Int64 = 0
  private var done = false

  private static let chunk = 512 * 1024

  init(request: AVAssetResourceLoadingRequest, owner: CachingResourceLoader) {
    self.request = request
    self.owner = owner
  }

  func start() {
    let key = owner.cacheKey
    let info = owner.cache.info(key)
    if let length = info.length { fillContentInformation(length: length, type: info.type) }
    guard let dataRequest = request.dataRequest else {
      if info.length != nil {
        finish(nil)
      } else {
        // Only content information was asked: one byte reveals it.
        offset = 0
        end = 1
        download = owner.startDownload(for: self, from: 0, to: 1)
      }
      return
    }
    offset = dataRequest.currentOffset
    if dataRequest.requestsAllDataToEndOfResource {
      end = info.length
    } else {
      end = dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
    }
    serve()
  }

  func cancel() {
    done = true
    download?.cancel()
    download = nil
  }

  /// Answers from the cache as far as possible, then downloads the rest.
  private func serve() {
    guard !done else { return }
    let key = owner.cacheKey
    while end.map({ offset < $0 }) ?? true {
      let available = owner.cache.contiguousBytes(key, from: offset)
      guard available > 0 else { break }
      let limit = end.map { $0 - offset } ?? available
      let length = Int(min(available, limit, Int64(Self.chunk)))
      guard let data = owner.cache.read(key, offset: offset, length: length), !data.isEmpty
      else { break }
      request.dataRequest?.respond(with: data)
      offset += Int64(data.count)
    }
    if let end, offset >= end {
      finish(nil)
      return
    }
    download = owner.startDownload(for: self, from: offset, to: end)
  }

  /// Returns false to cancel the transfer.
  func didReceive(_ response: URLResponse) -> Bool {
    guard !done else { return false }
    guard let http = response as? HTTPURLResponse else {
      finish(URLError(.badServerResponse))
      return false
    }
    guard (200..<300).contains(http.statusCode) else {
      let code: URLError.Code =
        http.statusCode == 404 || http.statusCode == 410 ? .fileDoesNotExist : .badServerResponse
      finish(URLError(code))
      return false
    }
    let type = http.mimeType
    var total: Int64?
    if http.statusCode == 206,
      let range = http.value(forHTTPHeaderField: "Content-Range"),
      let slash = range.lastIndex(of: "/")
    {
      total = Int64(range[range.index(after: slash)...])
    } else if http.statusCode == 200 {
      // The server ignored the range and sends the whole file.
      total = http.expectedContentLength > 0 ? http.expectedContentLength : nil
      skip = offset
      offset = 0
    }
    owner.cache.setInfo(owner.cacheKey, length: total, type: type)
    if let total {
      fillContentInformation(length: total, type: type)
      if end == nil || end! > total { end = total }
    }
    return true
  }

  func didReceive(_ data: Data) {
    guard !done, !data.isEmpty else { return }
    // Everything received is valid file content and is cached, including a
    // prefix that a server without range support sent before the bytes
    // AVFoundation asked for.
    owner.cache.write(owner.cacheKey, offset: offset, data: data)
    let start = offset
    offset += Int64(data.count)
    if request.dataRequest != nil {
      let from = max(start, skip)
      var to = offset
      if let end { to = min(to, end) }
      if to > from {
        let slice = data.subdata(in: Int(from - start)..<Int(to - start))
        request.dataRequest?.respond(with: slice)
      }
    }
    if let end, offset >= end {
      download?.cancel()
      finish(nil)
    }
  }

  func didComplete(_ error: Error?) {
    guard !done else { return }
    if let error = error as? URLError, error.code == .cancelled { return }
    finish(error)
  }

  private func fillContentInformation(length: Int64, type: String?) {
    guard let info = request.contentInformationRequest, info.contentLength == 0 else { return }
    info.contentLength = length
    info.isByteRangeAccessSupported = true
    info.contentType =
      type.flatMap { UTType(mimeType: $0)?.identifier } ?? UTType.mpeg4Movie.identifier
  }

  private func finish(_ error: Error?) {
    guard !done else { return }
    done = true
    if let error {
      request.finishLoading(with: error)
    } else {
      request.finishLoading()
    }
    owner.finished(self)
  }
}
