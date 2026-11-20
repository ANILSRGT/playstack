import AVFoundation
import Foundation

/// Gets the keys of a FairPlay Streaming asset: downloads the application
/// certificate, asks the license server for each key with the request data
/// (SPC) and hands the response (CKC) to AVFoundation.
///
/// Lives as long as the asset; `NativePlayer` keeps it with the source.
final class FairPlayKeyLoader: NSObject, AVContentKeySessionDelegate {
  static let errorDomain = "PlayStackDRM"

  private let drm: PlatformDrm
  private let session: AVContentKeySession
  private let queue = DispatchQueue(label: "dev.playstack.fairplay")
  private var certificate: Data?

  init(drm: PlatformDrm, asset: AVURLAsset) throws {
    guard drm.certificateUrl != nil, drm.licenseUrl != nil else {
      throw PigeonError(
        code: "drm", message: "FairPlay needs a certificate URL and a license URL.", details: nil)
    }
    self.drm = drm
    session = AVContentKeySession(keySystem: .fairPlayStreaming)
    super.init()
    session.setDelegate(self, queue: queue)
    session.addContentKeyRecipient(asset)
  }

  func close() {
    session.setDelegate(nil, queue: nil)
    session.expire()
  }

  // MARK: AVContentKeySessionDelegate

  func contentKeySession(
    _ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest
  ) {
    handle(keyRequest)
  }

  func contentKeySession(
    _ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
  ) {
    handle(keyRequest)
  }

  func contentKeySession(
    _ session: AVContentKeySession, contentKeyRequest keyRequest: AVContentKeyRequest,
    didFailWithError err: Error
  ) {}

  // MARK: Key exchange

  private func handle(_ request: AVContentKeyRequest) {
    let keyURI = (request.identifier as? String) ?? ""
    let contentId =
      drm.contentId ?? URL(string: keyURI)?.host
      ?? keyURI.replacingOccurrences(of: "skd://", with: "")
    loadCertificate { [weak self] result in
      guard let self else { return }
      switch result {
      case .failure(let error):
        request.processContentKeyResponseError(error)
      case .success(let certificate):
        request.makeStreamingContentKeyRequestData(
          forApp: certificate, contentIdentifier: Data(contentId.utf8),
          options: [AVContentKeyRequestProtocolVersionsKey: [1]]
        ) { spc, error in
          guard let spc else {
            request.processContentKeyResponseError(
              error ?? Self.failure("The key request could not be created."))
            return
          }
          self.requestLicense(spc) { result in
            switch result {
            case .success(let ckc):
              request.processContentKeyResponse(
                AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc))
            case .failure(let error):
              request.processContentKeyResponseError(error)
            }
          }
        }
      }
    }
  }

  private func loadCertificate(_ completion: @escaping (Result<Data, Error>) -> Void) {
    if let certificate {
      completion(.success(certificate))
      return
    }
    guard let url = drm.certificateUrl.flatMap(URL.init(string:)) else {
      completion(.failure(Self.failure("Invalid certificate URL.")))
      return
    }
    var request = URLRequest(url: url)
    drm.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    fetch(request) { [weak self] result in
      if case .success(let data) = result {
        self?.queue.async { self?.certificate = data }
      }
      completion(result)
    }
  }

  private func requestLicense(_ spc: Data, completion: @escaping (Result<Data, Error>) -> Void) {
    guard let url = drm.licenseUrl.flatMap(URL.init(string:)) else {
      completion(.failure(Self.failure("Invalid license URL.")))
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = spc
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    drm.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    fetch(request, completion: completion)
  }

  private func fetch(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error {
        completion(.failure(error))
        return
      }
      let status = (response as? HTTPURLResponse)?.statusCode ?? 200
      guard let data, (200..<300).contains(status) else {
        completion(.failure(Self.failure("The license server answered HTTP \(status).")))
        return
      }
      completion(.success(data))
    }.resume()
  }

  static func failure(_ message: String) -> NSError {
    NSError(domain: errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
