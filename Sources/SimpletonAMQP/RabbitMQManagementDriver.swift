// Sources/SimpletonAMQP/RabbitMQManagementDriver.swift
import Foundation
import SimpletonCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// RabbitMQ management backend over the HTTP Management API (`http(s)://host:15672/api`), using
/// Foundation `URLSession` — no AMQP client library. Every request carries an
/// `Authorization: Basic base64(user:password)` header; vhost + resource names are strictly
/// percent-encoded into the path (default vhost `/` → `%2F`). Failures are mapped to `AMQPError`.
///
/// `@unchecked Sendable`: all stored properties are immutable value types / an immutable `URLSession`
/// created once in `init`, so the type is safe to share across tasks.
public final class RabbitMQManagementDriver: AMQPManagementBackend, @unchecked Sendable {
    private let baseURL: URL
    private let authHeader: String
    private let session: URLSession

    /// Build a driver from a saved `Connection` + its Keychain `ConnectionSecret`.
    /// - Host/port come from the connection (default port 15672, or 15671 when `params["useTLS"]`).
    /// - User comes from the connection; password from the secret.
    /// - `params["useTLS"] == "true"` switches to https; `params["allowSelfSigned"] == "true"`
    ///   accepts an untrusted server certificate (self-signed dev brokers).
    public init(connection c: Connection, secret: ConnectionSecret?) throws {
        let useTLS = c.params["useTLS"] == "true"
        let scheme = useTLS ? "https" : "http"
        let host = c.host ?? "localhost"
        let port = c.port ?? (useTLS ? 15671 : 15672)
        guard let url = URL(string: "\(scheme)://\(host):\(port)") else {
            throw AMQPError.connectionFailed("invalid host/port: \(host):\(port)")
        }
        self.baseURL = url
        self.authHeader = RabbitMQManagementDriver.basicAuthHeader(
            user: c.username ?? "", password: secret?.password ?? "")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        if useTLS, c.params["allowSelfSigned"] == "true" {
            self.session = URLSession(
                configuration: config, delegate: InsecureTLSDelegate(), delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: config)
        }
    }

    deinit {
        // A delegate-backed URLSession (the allow-self-signed path) strongly retains its delegate
        // until invalidated, so release it when the driver is dropped on disconnect/reconnect.
        session.finishTasksAndInvalidate()
    }

    /// Testing/inspection seam: build the exact `Authorization` header value for Basic auth.
    /// `Basic base64("user:password")`.
    public static func basicAuthHeader(user: String, password: String) -> String {
        let raw = "\(user):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    /// Strict percent-encoding for a single path segment (a vhost or a resource name). Encodes
    /// everything outside the RFC 3986 *unreserved* set — crucially `/` → `%2F`, so the default
    /// vhost `/` and names containing slashes survive the path. Exposed for CoreChecks.
    public static func encodeSegment(_ s: String) -> String {
        // Unreserved per RFC 3986 §2.3: ALPHA / DIGIT / "-" / "." / "_" / "~". Everything else
        // (including "/") is percent-encoded so it stays a single path segment.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: - AMQPManagementBackend

    public func overview() async throws -> Overview {
        try await get("/api/overview")
    }

    public func queues(vhost: String) async throws -> [QueueInfo] {
        try await get("/api/queues/\(Self.encodeSegment(vhost))")
    }

    public func exchanges(vhost: String) async throws -> [ExchangeInfo] {
        try await get("/api/exchanges/\(Self.encodeSegment(vhost))")
    }

    public func connections() async throws -> [ConnectionInfo] {
        try await get("/api/connections")
    }

    public func channels() async throws -> [ChannelInfo] {
        try await get("/api/channels")
    }

    public func getMessages(vhost: String, queue: String, count: Int) async throws -> [MessagePreview] {
        let path = "/api/queues/\(Self.encodeSegment(vhost))/\(Self.encodeSegment(queue))/get"
        let body: [String: AnyEncodable] = [
            "count": AnyEncodable(max(1, count)),
            "ackmode": AnyEncodable("ack_requeue_true"),
            "encoding": AnyEncodable("auto"),
            "truncate": AnyEncodable(50000),
        ]
        let data = try await send(path, method: "POST", jsonBody: body)
        do {
            return try JSONDecoder().decode([MessagePreview].self, from: data)
        } catch {
            throw AMQPError.decodeFailed("get-messages: \(error)")
        }
    }

    @discardableResult
    public func publish(vhost: String, exchange: String, routingKey: String, payload: String) async throws -> Bool {
        let path = "/api/exchanges/\(Self.encodeSegment(vhost))/\(Self.encodeSegment(exchange))/publish"
        let body: [String: AnyEncodable] = [
            "properties": AnyEncodable([String: String]()),
            "routing_key": AnyEncodable(routingKey),
            "payload": AnyEncodable(payload),
            "payload_encoding": AnyEncodable("string"),
        ]
        let data = try await send(path, method: "POST", jsonBody: body)
        struct PublishResponse: Decodable { let routed: Bool }
        guard let decoded = try? JSONDecoder().decode(PublishResponse.self, from: data) else {
            // A 2xx with an unexpected shape still means the publish was accepted.
            return true
        }
        return decoded.routed
    }

    public func purge(vhost: String, queue: String) async throws {
        let path = "/api/queues/\(Self.encodeSegment(vhost))/\(Self.encodeSegment(queue))/contents"
        _ = try await send(path, method: "DELETE", jsonBody: [String: AnyEncodable]())
    }

    // MARK: - HTTP plumbing

    /// GET + JSON-decode into `T`.
    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(path, method: "GET", jsonBody: nil)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AMQPError.decodeFailed("\(path): \(error)")
        }
    }

    /// Perform a request, mapping transport + HTTP-status failures onto `AMQPError`, and return the
    /// response body on 2xx.
    private func send(_ path: String, method: String, jsonBody: [String: AnyEncodable]?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw AMQPError.connectionFailed("invalid path: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(jsonBody)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AMQPError.connectionFailed("\(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw AMQPError.connectionFailed("no HTTP response")
        }
        try RabbitMQManagementDriver.mapStatus(http.statusCode, body: data)
        return data
    }

    /// Map an HTTP status to an `AMQPError` (throwing) or return for 2xx. Exposed for CoreChecks so
    /// the status→error mapping is testable without a live broker.
    public static func mapStatus(_ status: Int, body: Data) throws {
        switch status {
        case 200...299:
            return
        case 401, 403:
            throw AMQPError.auth("authentication failed (HTTP \(status)) — check user/password")
        case 404:
            throw AMQPError.notFound("not found (HTTP 404) — vhost/queue/exchange may not exist")
        default:
            let text = String(data: body, encoding: .utf8) ?? ""
            throw AMQPError.requestFailed(status: status, body: String(text.prefix(200)))
        }
    }
}

/// Type-erased `Encodable` so a heterogeneous JSON body can be built from a `[String: …]` literal.
struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeClosure = value.encode }
    func encode(to encoder: Encoder) throws { try encodeClosure(encoder) }
}

/// Accepts an untrusted (e.g. self-signed) server certificate. Only installed when the connection
/// opts in via `params["allowSelfSigned"] == "true"` for a TLS broker; the default session performs
/// normal certificate validation.
private final class InsecureTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
