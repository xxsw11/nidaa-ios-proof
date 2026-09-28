import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TrialEnvironment: Sendable, Equatable {
    public let baseURL: URL
    public var id: String { baseURL.absoluteString }
    public init(baseURL: URL) throws {
        guard Self.validBase(baseURL), ["127.0.0.1", "localhost", "::1", "[::1]"].contains(baseURL.host ?? "") else { throw ClientError.invalidEnvironment }
        self.baseURL = baseURL
    }
    private init(isolatedURL: URL) { baseURL = isolatedURL }
    #if os(Linux)
    public static func isolatedLinux(baseURL: URL) throws -> TrialEnvironment {
        if let local = try? TrialEnvironment(baseURL: baseURL) { return local }
        guard validBase(baseURL), baseURL.host == "gateway", baseURL.port == 8080, baseURL.scheme == "http" else { throw ClientError.invalidEnvironment }
        return TrialEnvironment(isolatedURL: baseURL)
    }
    #endif
    private static func validBase(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme ?? "") && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil && ["", "/"].contains(url.path)
    }
    func url(_ path: String) -> URL { baseURL.appendingPathComponent(path) }
    func permits(_ url: URL) -> Bool { url.scheme == baseURL.scheme && url.host == baseURL.host && url.port == baseURL.port }
}

public struct HTTPResult: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
}
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        return HTTPResult(status: http.statusCode, body: data)
    }
}
