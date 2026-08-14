// Sources/SimpletonS3/SotoS3Backend.swift
import Foundation
import SimpletonCore
import SotoS3

/// S3 backend over Soto's pure-Swift AWS SDK (SotoS3, pinned 7.15.0). Holds one `AWSClient` + `S3`
/// service for the instance's lifetime; `close()` shuts the client down exactly once (Soto asserts
/// in `deinit` otherwise). `@unchecked Sendable`: `AWSClient`/`S3` are themselves `Sendable`, and the
/// `didShutdown` flag is only flipped inside the single `close()` call.
public final class SotoS3Backend: S3Backend, @unchecked Sendable {
    private let client: AWSClient
    private let s3: S3
    private var didShutdown = false

    /// Build the client + service from a `.s3` connection. Reads `params["endpoint"]` (optional, for
    /// MinIO / S3-compatible), `params["region"]` (default us-east-1), `params["pathStyle"]` (bool);
    /// credentials come from `secret.accessKey` / `secret.secretKey`.
    public init(connection: Connection, secret: ConnectionSecret?) {
        let accessKey = secret?.accessKey ?? ""
        let secretKey = secret?.secretKey ?? ""
        self.client = AWSClient(
            credentialProvider: .static(accessKeyId: accessKey, secretAccessKey: secretKey))

        let region = Region(rawValue: connection.params["region"].flatMap { $0.isEmpty ? nil : $0 } ?? "us-east-1")
        let endpoint = connection.params["endpoint"].flatMap { $0.isEmpty ? nil : $0 }
        // Soto uses path-style addressing whenever a custom endpoint is set (what MinIO / most
        // S3-compatible servers want). `pathStyle == false` opts back into virtual-host addressing.
        let pathStyle = (connection.params["pathStyle"] ?? "true") != "false"
        let options: AWSServiceConfig.Options = pathStyle ? [] : [.s3ForceVirtualHost]
        self.s3 = S3(client: client, region: region, endpoint: endpoint, options: options)
    }

    public func connect() async throws {
        // Lightweight reachability + credential check, so a bad key/endpoint fails here rather than
        // when the panel first lists a bucket.
        _ = try await listBuckets()
    }

    public func listBuckets() async throws -> [S3Bucket] {
        do {
            let out = try await s3.listBuckets()
            return (out.buckets ?? []).compactMap { b in
                guard let name = b.name else { return nil }
                return S3Bucket(name: name, creationDate: b.creationDate)
            }
        } catch {
            throw Self.map(error)
        }
    }

    public func list(bucket: String, prefix: String, continuationToken: String?) async throws -> S3ListPage {
        do {
            let out = try await s3.listObjectsV2(
                bucket: bucket,
                continuationToken: continuationToken,
                delimiter: "/",
                prefix: prefix.isEmpty ? nil : prefix)
            let objects: [S3Object] = (out.contents ?? []).compactMap { o in
                guard let key = o.key else { return nil }
                // S3 returns the prefix itself as a zero-byte "directory marker" object when one was
                // created explicitly; skip it so it doesn't show as a 0-byte file next to the folder.
                if key == prefix { return nil }
                return S3Object(
                    key: key, size: o.size ?? 0, lastModified: o.lastModified, etag: o.eTag, isPrefix: false)
            }
            let prefixes = (out.commonPrefixes ?? []).compactMap { $0.prefix }
            return S3ListPage(
                objects: objects, commonPrefixes: prefixes, nextToken: out.nextContinuationToken)
        } catch {
            throw Self.map(error)
        }
    }

    public func download(bucket: String, key: String) async throws -> Data {
        do {
            let out = try await s3.getObject(bucket: bucket, key: key)
            // Cap the in-memory collect at 5 GiB — the panel downloads to a user-chosen file and S3
            // objects over this size should stream; this bound just prevents an unbounded allocation.
            let buffer = try await out.body.collect(upTo: 5 * 1024 * 1024 * 1024)
            return Data(buffer: buffer)
        } catch {
            throw Self.map(error)
        }
    }

    public func upload(bucket: String, key: String, data: Data) async throws {
        do {
            _ = try await s3.putObject(
                body: .init(bytes: data),
                bucket: bucket,
                contentLength: Int64(data.count),
                key: key)
        } catch {
            throw Self.map(error)
        }
    }

    public func delete(bucket: String, key: String) async throws {
        do {
            _ = try await s3.deleteObject(bucket: bucket, key: key)
        } catch {
            throw Self.map(error)
        }
    }

    public func presignGetURL(bucket: String, key: String, expires: TimeInterval) async throws -> URL {
        do {
            let base = s3.endpoint
            // Path-style URL against the service endpoint; Soto's signer rewrites host per the
            // service options (path vs virtual-host) before signing, so this is correct for both.
            guard let url = URL(string: "\(base)/\(bucket)/\(Self.encodePath(key))") else {
                throw S3Error.connectionFailed("could not build object URL for \(key)")
            }
            return try await s3.signURL(
                url: url, httpMethod: .GET, expires: .seconds(Int64(max(1, expires))))
        } catch let e as S3Error {
            throw e
        } catch {
            throw Self.map(error)
        }
    }

    public func close() async {
        guard !didShutdown else { return }
        didShutdown = true
        try? await client.shutdown()
    }

    // MARK: - helpers

    /// Percent-encode each path segment of an object key for the presign URL, preserving the `/`
    /// separators (they must stay literal so the path structure survives signing).
    private static func encodePath(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false)
            .map { seg in
                String(seg).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(seg)
            }
            .joined(separator: "/")
    }

    /// Map any thrown error to `S3Error`. Recognized AWS error codes / HTTP statuses become
    /// `.auth` / `.notFound`; everything else (transport, DNS, TLS, timeouts) is `.connectionFailed`.
    static func map(_ error: Error) -> S3Error {
        if let e = error as? S3Error { return e }
        if let aws = error as? AWSErrorType {
            let code = aws.errorCode
            let status = aws.context?.responseCode.code
            let message = aws.context?.message ?? code
            switch code {
            case "NoSuchBucket", "NoSuchKey", "NotFound":
                return .notFound(message)
            case "AccessDenied", "InvalidAccessKeyId", "SignatureDoesNotMatch", "InvalidToken",
                "ExpiredToken", "AuthorizationHeaderMalformed", "AccountProblem":
                return .auth(message)
            default:
                if status == 404 { return .notFound(message) }
                if status == 401 || status == 403 { return .auth(message) }
                return .connectionFailed(message)
            }
        }
        return .connectionFailed("\(error)")
    }
}
