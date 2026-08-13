// Tests/CoreChecks/S3DriverChecks.swift
import Foundation
import SimpletonCore
import SimpletonS3

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
