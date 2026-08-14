// Sources/SimpletonS3/S3Backend.swift
import Foundation

/// The backend-agnostic interface for an S3 (or S3-compatible) object store. All I/O is async and
/// runs off the main actor; backends map every failure to `S3Error` so no raw SDK / transport error
/// escapes. Mirrors `SQLDriver` in `SimpletonSQL`.
public protocol S3Backend: AnyObject, Sendable {
    /// Validate credentials / reachability (a lightweight `listBuckets`), so a failed connect is
    /// surfaced before the panel shows a bucket list.
    func connect() async throws
    func listBuckets() async throws -> [S3Bucket]
    /// One page of a prefix listing. `prefix` is the folder path (e.g. `"logs/2026/"`); the backend
    /// uses `delimiter: "/"` so sub-folders come back as `commonPrefixes`. Pass `continuationToken`
    /// from a prior page's `nextToken` to page forward.
    func list(bucket: String, prefix: String, continuationToken: String?) async throws -> S3ListPage
    func download(bucket: String, key: String) async throws -> Data
    func upload(bucket: String, key: String, data: Data) async throws
    func delete(bucket: String, key: String) async throws
    /// A time-limited presigned GET URL for `key`, usable by any HTTP client without credentials.
    func presignGetURL(bucket: String, key: String, expires: TimeInterval) async throws -> URL
    /// Release the underlying AWS client. MUST be called exactly once; the concrete backend calls
    /// `AWSClient.shutdown()` here (leaks / asserts otherwise).
    func close() async
}

/// A bucket in the account/endpoint.
public struct S3Bucket: Sendable, Hashable {
    public let name: String
    public let creationDate: Date?
    public init(name: String, creationDate: Date? = nil) {
        self.name = name
        self.creationDate = creationDate
    }
}

/// An object or a folder-style prefix row within a bucket listing. `isPrefix == true` marks a
/// "folder" (a common prefix) — it has no size/date and navigating into it re-lists with that prefix.
public struct S3Object: Sendable, Hashable {
    public let key: String
    public let size: Int64
    public let lastModified: Date?
    public let etag: String?
    public let isPrefix: Bool

    public init(key: String, size: Int64, lastModified: Date? = nil, etag: String? = nil, isPrefix: Bool = false) {
        self.key = key
        self.size = size
        self.lastModified = lastModified
        self.etag = etag
        self.isPrefix = isPrefix
    }

    /// The trailing path component of `key` relative to `prefix` — the display name for a table row.
    /// For a folder ("logs/2026/") under prefix "logs/" this is "2026/".
    public func displayName(under prefix: String) -> String {
        let stripped = key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
        return stripped.isEmpty ? key : stripped
    }
}

/// One page of a prefix listing: the concrete objects, the sub-folder prefixes, and a token to fetch
/// the next page (nil = last page).
public struct S3ListPage: Sendable, Hashable {
    public let objects: [S3Object]
    public let commonPrefixes: [String]
    public let nextToken: String?

    public init(objects: [S3Object], commonPrefixes: [String], nextToken: String? = nil) {
        self.objects = objects
        self.commonPrefixes = commonPrefixes
        self.nextToken = nextToken
    }
}

/// Every failure a backend can produce, normalized so the panel never sees a raw Soto/NIO error.
public enum S3Error: Error, Sendable, Equatable {
    /// Bad/expired credentials or a signature mismatch (HTTP 401/403, InvalidAccessKeyId, …).
    case auth(String)
    /// The bucket or key does not exist (HTTP 404, NoSuchBucket, NoSuchKey).
    case notFound(String)
    /// A transport-level failure (DNS, TLS, connection refused, timeout) or any other error.
    case connectionFailed(String)
    /// The connection is not an S3 connection (factory rejects non-`.s3` kinds).
    case unsupported(String)
}

/// Byte-size formatting shared by the model and the panel, so table rows and the CoreChecks test use
/// one implementation. Uses `ByteCountFormatter` (binary units → "1.5 MB").
public enum S3Format {
    public static func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
