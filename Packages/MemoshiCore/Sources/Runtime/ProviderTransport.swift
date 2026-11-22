import Foundation
import PiAI
import PiCore
import Synchronization

/// A refused provider redirect. The credential lease checks the first hop only, so a redirect
/// that URLSession followed could carry the key's header to another host.
struct ProviderRedirectRefused: Error, Sendable {}

/// URLSession transport for credentialed provider requests: responses stream as they arrive,
/// as PiAI's own transport does, but no redirect is ever followed. A redirect fails the request
/// before anything is sent to its location.
final class RedirectRefusingFetch: Sendable {
  private let session: URLSession

  init(idleTimeoutMs: Int = PiAI.DEFAULT_HTTP_IDLE_TIMEOUT_MS) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.timeoutIntervalForRequest = Double(idleTimeoutMs) / 1_000
    session = URLSession(configuration: configuration)
  }

  deinit { session.invalidateAndCancel() }

  var fetch: PiAI.FetchFunction {
    { [self] request, signal in try await self.send(request, signal: signal) }
  }

  private func send(_ request: PiAI.HTTPRequest, signal: PiCore.AbortSignal?) async throws
    -> PiAI.HTTPResponse
  {
    try signal?.throwIfAborted()
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    for header in request.headers {
      urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
    }
    urlRequest.httpBody = request.body
    if let timeout = request.timeoutMs, timeout > 0 {
      urlRequest.timeoutInterval = Double(timeout) / 1_000
    }
    let delegate = RedirectRefusingTask()
    let task = session.dataTask(with: urlRequest)
    task.delegate = delegate
    delegate.cancelBody(with: task)
    let token = signal?.addListener { _ in task.cancel() }
    delegate.whenComplete { if let token { signal?.removeListener(token) } }
    return try await withTaskCancellationHandler {
      task.resume()
      let response = try await delegate.response()
      var headers: [String: String] = [:]
      for (key, value) in response.allHeaderFields {
        if let name = key as? String { headers[name.lowercased()] = "\(value)" }
      }
      return PiAI.HTTPResponse(
        status: response.statusCode, headers: headers, url: response.url,
        body: PiAI.HTTPBody(delegate.body))
    } onCancel: {
      task.cancel()
    }
  }
}

/// Bridges one task's URLSession callbacks to a response and a streamed body.
private final class RedirectRefusingTask: NSObject, URLSessionDataDelegate, Sendable {
  private struct State {
    var waiter: CheckedContinuation<HTTPURLResponse, any Error>?
    var response: Result<HTTPURLResponse, any Error>?
    var completions: [@Sendable () -> Void] = []
  }

  private let state = Mutex(State())
  let body: AsyncThrowingStream<Data, any Error>
  private let continuation: AsyncThrowingStream<Data, any Error>.Continuation

  override init() {
    (body, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    super.init()
  }

  func cancelBody(with task: URLSessionDataTask) {
    continuation.onTermination = { [weak task] termination in
      if case .cancelled = termination { task?.cancel() }
    }
  }

  func whenComplete(_ action: @escaping @Sendable () -> Void) {
    state.withLock { $0.completions.append(action) }
  }

  func response() async throws -> HTTPURLResponse {
    try await withCheckedThrowingContinuation { waiter in
      let ready = state.withLock { state -> Result<HTTPURLResponse, any Error>? in
        if let response = state.response { return response }
        state.waiter = waiter
        return nil
      }
      if let ready { waiter.resume(with: ready) }
    }
  }

  private func resolve(_ result: Result<HTTPURLResponse, any Error>) {
    let waiter = state.withLock { state -> CheckedContinuation<HTTPURLResponse, any Error>? in
      guard state.response == nil else { return nil }
      state.response = result
      defer { state.waiter = nil }
      return state.waiter
    }
    waiter?.resume(with: result)
  }

  /// Every redirect is refused: nothing is sent to its location, and the request fails.
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    resolve(.failure(ProviderRedirectRefused()))
    continuation.finish(throwing: ProviderRedirectRefused())
    completionHandler(nil)
    task.cancel()
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse else {
      resolve(.failure(PiAI.HTTPTransportError("Non-HTTP response")))
      completionHandler(.cancel)
      return
    }
    resolve(.success(http))
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    continuation.yield(data)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    if let error {
      resolve(.failure(error))
      continuation.finish(throwing: error)
    } else {
      resolve(.failure(PiAI.HTTPTransportError("Response ended before headers")))
      continuation.finish()
    }
    let completions = state.withLock { state in
      defer { state.completions = [] }
      return state.completions
    }
    for completion in completions { completion() }
  }
}
