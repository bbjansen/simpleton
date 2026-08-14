// Sources/SimpletonSFTP/KnownHosts.swift
import Foundation
import NIOCore
import NIOSSH

/// A single parsed line of an OpenSSH `known_hosts` file: one or more host patterns plus a key.
///
/// Format (per `sshd(8)` / `ssh_config(5)`): `hostpatterns keytype base64key [comment]`, e.g.
/// `example.com,192.0.2.1 ssh-ed25519 AAAAC3Nz...`. Non-default ports are written `[host]:port`.
/// Hashed (`|1|...`) and marker (`@revoked`, `@cert-authority`) lines are skipped — this is a
/// pragmatic TOFU store, not a full OpenSSH parser.
public struct KnownHostsLine: Sendable, Equatable {
    public let hostPatterns: [String]
    public let keyType: String
    public let base64Key: String

    public init(hostPatterns: [String], keyType: String, base64Key: String) {
        self.hostPatterns = hostPatterns
        self.keyType = keyType
        self.base64Key = base64Key
    }

    /// The `keytype base64key` token, i.e. the OpenSSH public-key string form (`String(openSSHPublicKey:)`).
    public var openSSHKeyString: String { "\(keyType) \(base64Key)" }
}

/// Pure, side-effect-free parsing/matching of `known_hosts` content. Kept free of NIO so it can be
/// unit-tested directly in CoreChecks.
public enum KnownHostsFile {
    /// Parse one line into a `KnownHostsLine`, or nil for blank/comment/hashed/marker/malformed lines.
    public static func parse(line raw: String) -> KnownHostsLine? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { return nil }
        // Skip @cert-authority / @revoked markers and hashed |1|... host fields — not supported.
        if line.hasPrefix("@") { return nil }
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count >= 3 else { return nil }
        if fields[0].hasPrefix("|") { return nil }
        let hosts = fields[0].split(separator: ",").map(String.init)
        guard !hosts.isEmpty else { return nil }
        return KnownHostsLine(hostPatterns: hosts, keyType: fields[1], base64Key: fields[2])
    }

    /// Parse a whole file's contents into lines (skipping non-matching content).
    public static func parse(contents: String) -> [KnownHostsLine] {
        contents.split(whereSeparator: \.isNewline).compactMap { parse(line: String($0)) }
    }

    /// The host pattern OpenSSH writes for a given host+port: bare host on 22, `[host]:port` otherwise.
    public static func hostPattern(host: String, port: Int) -> String {
        port == 22 ? host : "[\(host)]:\(port)"
    }

    /// The set of key strings (`keytype base64`) recorded for `host`/`port`.
    ///
    /// Matches OpenSSH semantics: a bare-host entry is associated with the default port 22, so on a
    /// non-standard port only the `[host]:port` form matches (a bare entry does not).
    public static func keys(for host: String, port: Int, in lines: [KnownHostsLine]) -> Set<String> {
        let pattern = hostPattern(host: host, port: port)
        var out = Set<String>()
        for line in lines where line.hostPatterns.contains(pattern) {
            out.insert(line.openSSHKeyString)
        }
        return out
    }
}

/// A Trust-On-First-Use host-key validator backed by `~/.ssh/known_hosts`.
///
/// - A key already recorded for the host → accept.
/// - A key of a type already recorded for the host, but with different bytes → reject (`.fail`): a
///   changed key is a possible MITM and is never silently trusted.
/// - An unknown host (no key recorded) → accept **and append** the key to `known_hosts` (creating it
///   `0600` if absent). This is the documented allow-on-first-use behaviour.
///
/// `NIOSSHClientServerAuthenticationDelegate.validateHostKey` is called on a NIO event-loop thread;
/// the file I/O here is synchronous and small, so it runs inline before completing the promise.
public final class KnownHostsValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let knownHostsURL: URL

    public init(host: String, port: Int, knownHostsURL: URL? = nil) {
        self.host = host
        self.port = port
        self.knownHostsURL =
            knownHostsURL
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/known_hosts")
    }

    public func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let offered = String(openSSHPublicKey: hostKey)  // "keytype base64"
        let offeredType = offered.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        let lines = readLines()
        let recorded = KnownHostsFile.keys(for: host, port: port, in: lines)

        if recorded.contains(offered) {
            validationCompletePromise.succeed(())
            return
        }
        // A recorded key of the SAME type but different bytes → the key changed; reject.
        if recorded.contains(where: { $0.hasPrefix(offeredType + " ") }) {
            validationCompletePromise.fail(
                SFTPError.hostKey(
                    "Host key for \(host) has CHANGED (\(offeredType)). "
                        + "This may indicate a man-in-the-middle attack. "
                        + "Remove the old entry from ~/.ssh/known_hosts if this change is expected."))
            return
        }
        // Unknown host → trust on first use and persist.
        do {
            try append(keyString: offered)
            validationCompletePromise.succeed(())
        } catch {
            validationCompletePromise.fail(
                SFTPError.hostKey("Could not record new host key for \(host): \(error)"))
        }
    }

    private func readLines() -> [KnownHostsLine] {
        guard let contents = try? String(contentsOf: knownHostsURL, encoding: .utf8) else { return [] }
        return KnownHostsFile.parse(contents: contents)
    }

    /// Append `hostpattern keytype base64` to `known_hosts`, creating the `.ssh` dir (`0700`) and the
    /// file (`0600`) if needed.
    private func append(keyString: String) throws {
        let pattern = KnownHostsFile.hostPattern(host: host, port: port)
        let entry = "\(pattern) \(keyString)\n"
        let fm = FileManager.default
        let dir = knownHostsURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(
                at: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        guard let data = entry.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: knownHostsURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: knownHostsURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: knownHostsURL.path)
        }
    }
}
