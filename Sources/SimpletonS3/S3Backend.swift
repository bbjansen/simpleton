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
    /// Upload a local file at `fileURL`, streamed from disk so multi-GB files never load fully into
    /// memory. Files at or above `S3Upload.multipartThreshold` go through S3 multipart upload (parts
    /// uploaded concurrently); smaller files use a single `putObject`. `progress` reports the fraction
    /// complete (0…1) and is called after each part; for the small-file path it is invoked once with
    /// `1.0` on success. The backend maps every failure to `S3Error`.
    func upload(
        bucket: String, key: String, fileURL: URL,
        progress: @escaping @Sendable (Double) async throws -> Void) async throws
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

/// Pure, side-effect-free upload policy: the size threshold that switches an upload from a single
/// `putObject` to a multipart upload, and the per-part size used for multipart. Kept free of any SDK
/// type so the decision is unit-testable (see CoreChecks) and shared by every backend.
public enum S3Upload {
    /// At or above this many bytes an upload uses S3 multipart; below it a single `putObject` is used.
    /// 8 MiB — comfortably above S3's 5 MiB minimum part size so a multipart upload always has at
    /// least one full-size part.
    public static let multipartThreshold: Int64 = 8 * 1024 * 1024

    /// S3 requires every multipart part except the last to be at least 5 MiB.
    public static let minimumPartSize: Int64 = 5 * 1024 * 1024

    /// S3 allows at most 10,000 parts per upload.
    public static let maximumPartCount: Int64 = 10_000

    /// Whether a file of `fileSize` bytes should use multipart upload. Zero/negative sizes never do.
    public static func shouldUseMultipart(fileSize: Int64) -> Bool {
        fileSize >= multipartThreshold
    }

    /// The part size (bytes) to use for a multipart upload of `fileSize` bytes. Starts at the 5 MiB
    /// minimum and grows just enough that the file fits within `maximumPartCount` parts, so even very
    /// large files (> 50 GiB) stay under the 10,000-part cap. Always ≥ `minimumPartSize`.
    public static func partSize(forFileSize fileSize: Int64) -> Int {
        guard fileSize > 0 else { return Int(minimumPartSize) }
        // ceil(fileSize / maximumPartCount), then rounded up to the next whole MiB, floored at 5 MiB.
        let needed = (fileSize + maximumPartCount - 1) / maximumPartCount
        let mib: Int64 = 1024 * 1024
        let roundedToMiB = ((needed + mib - 1) / mib) * mib
        return Int(max(minimumPartSize, roundedToMiB))
    }
}

/// Byte-size formatting shared by the model and the panel, so table rows and the CoreChecks test use
/// one implementation. Uses `ByteCountFormatter` (binary units → "1.5 MB").
public enum S3Format {
    public static func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
