// Tests/CoreChecks/S3DriverChecks.swift
import Foundation
import SimpletonCore
import SimpletonS3

/// Thread-safe recorder for the upload progress callback, which Soto invokes off the calling task.
/// Guards its state with a lock so the `@Sendable` closure can accumulate without a data race.
private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _last = -1.0
    private var _saw = false
    private var _monotonic = true

    func record(_ fraction: Double) {
        lock.lock()
        defer { lock.unlock() }
        if _saw, fraction < _last { _monotonic = false }
        _saw = true
        _last = fraction
    }

    var sawProgress: Bool { lock.withLock { _saw } }
    var monotonic: Bool { lock.withLock { _monotonic } }
    var lastFraction: Double { lock.withLock { _last } }
}

func runS3DriverChecks(_ t: TestRunner) async {
    t.suite("S3Object isPrefix + displayName") {
        let folder = S3Object(key: "logs/2026/", size: 0, isPrefix: true)
        t.expect(folder.isPrefix, "folder row is a prefix")
        t.expectEqual(folder.displayName(under: "logs/"), "2026/", "folder display name relative to prefix")
        let file = S3Object(key: "logs/2026/app.log", size: 42, isPrefix: false)
        t.expect(!file.isPrefix, "file row is not a prefix")
        t.expectEqual(file.displayName(under: "logs/2026/"), "app.log", "file display name relative to prefix")
        t.expectEqual(file.displayName(under: ""), "logs/2026/app.log", "display name under empty prefix is full key")
    }

    t.suite("S3Format.humanSize") {
        t.expectEqual(S3Format.humanSize(0), "Zero KB", "zero bytes")
        t.expect(S3Format.humanSize(1_500_000).contains("MB"), "megabyte-scale renders MB")
        t.expect(S3Format.humanSize(2_000_000_000).contains("GB"), "gigabyte-scale renders GB")
    }

    t.suite("S3ListPage shape") {
        let page = S3ListPage(
            objects: [S3Object(key: "a.txt", size: 10, isPrefix: false)],
            commonPrefixes: ["sub/"],
            nextToken: "tok-1")
        t.expectEqual(page.objects.count, 1, "one object")
        t.expectEqual(page.commonPrefixes, ["sub/"], "one common prefix")
        t.expectEqual(page.nextToken, "tok-1", "next token carried")
        let last = S3ListPage(objects: [], commonPrefixes: [])
        t.expect(last.nextToken == nil, "last page has no next token")
    }

    t.suite("S3Bucket model") {
        let now = Date()
        let b = S3Bucket(name: "backups", creationDate: now)
        t.expectEqual(b.name, "backups", "bucket name")
        t.expectEqual(b.creationDate, now, "bucket creation date")
    }

    t.suite("S3Upload.shouldUseMultipart threshold") {
        t.expectEqual(S3Upload.multipartThreshold, 8 * 1024 * 1024, "threshold is 8 MiB")
        t.expect(!S3Upload.shouldUseMultipart(fileSize: 0), "empty file is single putObject")
        t.expect(
            !S3Upload.shouldUseMultipart(fileSize: S3Upload.multipartThreshold - 1),
            "just under threshold is single putObject")
        t.expect(
            S3Upload.shouldUseMultipart(fileSize: S3Upload.multipartThreshold),
            "exactly at threshold is multipart")
        t.expect(
            S3Upload.shouldUseMultipart(fileSize: 100 * 1024 * 1024),
            "100 MiB is multipart")
        t.expect(!S3Upload.shouldUseMultipart(fileSize: -1), "negative size never multipart")
    }

    t.suite("S3Upload.partSize math") {
        // Small multipart files use the 5 MiB minimum part size.
        t.expectEqual(
            S3Upload.partSize(forFileSize: S3Upload.multipartThreshold), Int(S3Upload.minimumPartSize),
            "8 MiB file uses 5 MiB minimum part size")
        t.expectEqual(
            S3Upload.partSize(forFileSize: 0), Int(S3Upload.minimumPartSize),
            "zero size falls back to minimum part size")
        // Part size is always at least the 5 MiB minimum and a whole number of MiB.
        let mib = 1024 * 1024
        let sizes: [Int64] = [
            9 * 1024 * 1024, 50 * 1024 * 1024, 5 * 1024 * 1024 * 1024, 100 * 1024 * 1024 * 1024,
        ]
        for size in sizes {
            let part = S3Upload.partSize(forFileSize: size)
            t.expect(part >= Int(S3Upload.minimumPartSize), "part size >= 5 MiB for \(size) bytes")
            t.expectEqual(part % mib, 0, "part size is a whole MiB for \(size) bytes")
            // The whole file must fit within S3's 10,000-part cap at this part size.
            let parts = (size + Int64(part) - 1) / Int64(part)
            t.expect(parts <= S3Upload.maximumPartCount, "\(size) bytes fits in <= 10000 parts (got \(parts))")
        }
        // A very large file (> 50 GiB) must grow the part size beyond the minimum to stay under the cap.
        let huge: Int64 = 60 * 1024 * 1024 * 1024
        t.expect(
            S3Upload.partSize(forFileSize: huge) > Int(S3Upload.minimumPartSize),
            "60 GiB file grows part size above minimum")
    }

    // Env-gated live check against MinIO / any S3-compatible endpoint.
    if let endpoint = ProcessInfo.processInfo.environment["SIMPLETON_S3_TEST_ENDPOINT"],
        let key = ProcessInfo.processInfo.environment["SIMPLETON_S3_TEST_KEY"],
        let secret = ProcessInfo.processInfo.environment["SIMPLETON_S3_TEST_SECRET"]
    {
        await t.suite("SotoS3Backend listBuckets (integration)") {
            let region = ProcessInfo.processInfo.environment["SIMPLETON_S3_TEST_REGION"] ?? "us-east-1"
            let conn = Connection(
                name: "minio-test", kind: .s3,
                params: ["endpoint": endpoint, "region": region, "pathStyle": "true"])
            let sec = ConnectionSecret(accessKey: key, secretKey: secret)
            do {
                let backend = try S3BackendFactory.make(conn, secret: sec)
                try await backend.connect()
                let buckets = try await backend.listBuckets()
                t.expect(buckets.count >= 0, "listBuckets returned \(buckets.count) bucket(s)")
                await backend.close()
            } catch {
                t.expect(false, "unexpected error: \(error)")
            }
        }

        await t.suite("SotoS3Backend multipart upload (integration)") {
            let region = ProcessInfo.processInfo.environment["SIMPLETON_S3_TEST_REGION"] ?? "us-east-1"
            // Use a caller-provided bucket if set, else the first bucket the account exposes.
            let envBucket = ProcessInfo.processInfo.environment["SIMPLETON_S3_TEST_BUCKET"]
            let conn = Connection(
                name: "minio-test", kind: .s3,
                params: ["endpoint": endpoint, "region": region, "pathStyle": "true"])
            let sec = ConnectionSecret(accessKey: key, secretKey: secret)
            // A > 8 MiB temp file so the backend takes the multipart path (threshold is 8 MiB).
            let fileSize: Int64 = 10 * 1024 * 1024 + 123
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("simpleton-s3-multipart-\(UUID().uuidString).bin")
            let objectKey = "simpleton-tests/multipart-\(UUID().uuidString).bin"
            do {
                // Write a deterministic pattern without holding the whole file in memory.
                FileManager.default.createFile(atPath: tmp.path, contents: nil)
                let handle = try FileHandle(forWritingTo: tmp)
                let chunk = Data(repeating: 0xAB, count: 1024 * 1024)
                var written: Int64 = 0
                while written < fileSize {
                    let remaining = fileSize - written
                    let slice = remaining >= Int64(chunk.count) ? chunk : chunk.prefix(Int(remaining))
                    try handle.write(contentsOf: slice)
                    written += Int64(slice.count)
                }
                try handle.close()
                t.expect(
                    S3Upload.shouldUseMultipart(fileSize: fileSize),
                    "test file (\(fileSize) bytes) triggers multipart path")

                let backend = try S3BackendFactory.make(conn, secret: sec)
                defer { try? FileManager.default.removeItem(at: tmp) }
                do {
                    try await backend.connect()
                    let buckets = try await backend.listBuckets()
                    guard let bucket = envBucket ?? buckets.first?.name else {
                        t.expect(false, "no bucket available for multipart upload test")
                        await backend.close()
                        return
                    }

                    // The progress closure is `@Sendable` and runs off the calling task, so accumulate
                    // into a lock-guarded recorder rather than captured vars (data-race free).
                    let recorder = ProgressRecorder()
                    try await backend.upload(bucket: bucket, key: objectKey, fileURL: tmp) { fraction in
                        recorder.record(fraction)
                    }
                    t.expect(recorder.sawProgress, "progress callback fired")
                    t.expect(recorder.monotonic, "progress fractions were non-decreasing")
                    t.expect(
                        recorder.lastFraction <= 1.0 + 1e-9 && recorder.lastFraction >= 0,
                        "final fraction in 0…1")

                    // The object must list with the exact byte size we uploaded.
                    let prefix = "simpleton-tests/"
                    let page = try await backend.list(bucket: bucket, prefix: prefix, continuationToken: nil)
                    let uploaded = page.objects.first { $0.key == objectKey }
                    t.expect(uploaded != nil, "uploaded object appears in listing")
                    t.expectEqual(uploaded?.size ?? -1, fileSize, "listed object size matches uploaded bytes")

                    // Clean up the remote object.
                    try await backend.delete(bucket: bucket, key: objectKey)
                    let after = try await backend.list(bucket: bucket, prefix: prefix, continuationToken: nil)
                    t.expect(
                        !after.objects.contains { $0.key == objectKey },
                        "object removed after delete")
                    await backend.close()
                } catch {
                    await backend.close()
                    t.expect(false, "multipart upload flow failed: \(error)")
                }
            } catch {
                try? FileManager.default.removeItem(at: tmp)
                t.expect(false, "could not prepare multipart test file: \(error)")
            }
        }
    } else {
        print("  … S3 live checks skipped (set SIMPLETON_S3_TEST_ENDPOINT/KEY/SECRET to run)")
    }

    await t.suite("S3BackendFactory mapping") {
        do {
            let backend = try S3BackendFactory.make(
                Connection(name: "s3", kind: .s3, params: ["region": "us-east-1"]),
                secret: ConnectionSecret(accessKey: "a", secretKey: "b"))
            t.expect(backend is SotoS3Backend, "s3 → SotoS3Backend")
            await backend.close()
        } catch {
            t.expect(false, "s3 factory should not throw: \(error)")
        }
        do {
            _ = try S3BackendFactory.make(Connection(name: "pg", kind: .postgres), secret: nil)
            t.expect(false, "postgres should throw unsupported")
        } catch let e as S3Error {
            if case .unsupported = e {
                t.expect(true, "postgres → unsupported")
            } else {
                t.expect(false, "wrong error \(e)")
            }
        } catch {
            t.expect(false, "wrong error type: \(error)")
        }
    }
}
