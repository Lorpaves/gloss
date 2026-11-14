//
//  StubURLProtocol.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import Synchronization

/// Answers the requests of a test's URL session in place of the network.
///
/// Every test registers its own handler under a URL of its own, so tests running in parallel don't see each other's
/// requests.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    /// What the stub server sends back.
    struct Reply: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
        /// The connection fails with this once `body` is sent, as when it drops halfway through a file.
        var failure: URLError.Code?
    }

    typealias Handler = @Sendable (URLRequest) -> Reply

    private static let failureDelay = Duration.milliseconds(100)
    private static let handlers = Mutex<[String: Handler]>([:])
    private static let received = Mutex<[String: [URLRequest]]>([:])

    // MARK: - Test API

    /// Registers `handler` under a new URL and returns it.
    static func register(_ handler: @escaping Handler) -> URL {
        let address = "https://stub.gloss.test/\(UUID().uuidString)/model.bin"
        guard let url = URL(string: address) else {
            preconditionFailure("Malformed stub URL \(address)")
        }
        handlers.withLock { $0[address] = handler }
        return url
    }

    /// The requests made to `url` so far.
    static func requests(to url: URL) -> [URLRequest] {
        received.withLock { $0[url.absoluteString] ?? [] }
    }

    /// How many requests to the same URL came before `request`: 0 for the first attempt. For handlers that answer
    /// later attempts differently.
    static func earlierAttempts(before request: URLRequest) -> Int {
        request.url.map { requests(to: $0).count } ?? 0
    }

    /// A session configuration whose requests go to the stub.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let handler = Self.handlers.withLock({ $0[url.absoluteString] }),
              case let reply = handler(request),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: reply.status,
                  httpVersion: "HTTP/1.1",
                  headerFields: reply.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        Self.received.withLock { $0[url.absoluteString, default: []].append(request) }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        if let failure = reply.failure {
            // A moment later, the way a connection drops after part of a file has arrived. Failing in the same
            // instant makes the session throw the body away before handing it on.
            Task {
                try? await Task.sleep(for: Self.failureDelay)
                self.client?.urlProtocol(self, didFailWithError: URLError(failure))
            }
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
