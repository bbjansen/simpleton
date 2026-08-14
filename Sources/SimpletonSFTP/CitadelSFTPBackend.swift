// Sources/SimpletonSFTP/CitadelSFTPBackend.swift
import Citadel
import Crypto
import Foundation
import NIOCore
import NIOFoundationCompat
import NIOSSH
import SimpletonCore

/// SFTP backend over Citadel (SwiftNIO-SSH). Opens one `SSHClient` + `SFTPClient` per instance.
///
/// `@unchecked Sendable`: `client`/`sftp` are assigned once in `connect()` before any use, and every
/// method awaits on Citadel's own actor-safe API. Auth (password or public key) and host + port +
/// username are read from `Connection`/`ConnectionSecret`; secrets never touch `params`.
public final class CitadelSFTPBackend: SFTPBackend, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let username: String
    private let password: String?
    private let identityFile: String?
    private let passphrase: String?

    private var client: SSHClient?
    private var sftp: SFTPClient?

    public init(connection: Connection, secret: ConnectionSecret?) {
        self.host = connection.host ?? "localhost"
        self.port = connection.port ?? 22
        self.username = connection.username ?? ""
        self.password = secret?.password
        // Non-secret identity-file path lives in params; tilde-expanded like the app's SSH handling.
        if let raw = connection.params["identityFile"], !raw.isEmpty {
            self.identityFile = NSString(string: raw).expandingTildeInPath
        } else {
            self.identityFile = nil
        }
        self.passphrase = secret?.passphrase
    }

    // MARK: - lifecycle

    public func connect() async throws {
        let auth: SSHAuthenticationMethod
        do {
            auth = try makeAuthentication()
        } catch let e as SFTPError {
            throw e
        } catch {
            throw SFTPError.auth("Could not load identity file: \(error)")
        }

        let validator = SSHHostKeyValidator.custom(
            KnownHostsValidator(host: host, port: port))

        do {
            let ssh = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: auth,
                hostKeyValidator: validator,
                reconnect: .never)
            self.client = ssh
            self.sftp = try await ssh.openSFTP()
        } catch let e as SFTPError {
            throw e
        } catch {
            throw Self.mapConnectError(error)
        }
    }

    public func close() async {
        try? await sftp?.close()
        try? await client?.close()
        sftp = nil
        client = nil
    }

    // MARK: - auth

    private func makeAuthentication() throws -> SSHAuthenticationMethod {
        if let identityFile {
            guard let keyString = try? String(contentsOfFile: identityFile, encoding: .utf8) else {
                throw SFTPError.auth("Identity file not readable: \(identityFile)")
            }
            let pass = passphrase?.data(using: .utf8)
            let type: SSHKeyType
            do {
                type = try SSHKeyDetection.detectPrivateKeyType(from: keyString)
            } catch {
                throw SFTPError.auth("Unrecognized private key format in \(identityFile)")
            }
            switch type {
            case .ed25519:
                let key = try Curve25519.Signing.PrivateKey(sshEd25519: keyString, decryptionKey: pass)
                return .ed25519(username: username, privateKey: key)
            case .rsa:
                let key = try Insecure.RSA.PrivateKey(sshRsa: keyString, decryptionKey: pass)
                return .rsa(username: username, privateKey: key)
            default:
                throw SFTPError.auth(
                    "Unsupported key type \(type.description); use an ed25519 or RSA key, or password auth.")
            }
        }
        guard let password else {
            throw SFTPError.auth("No password or identity file configured for \(username)@\(host).")
        }
        return .passwordBased(username: username, password: password)
    }

    // MARK: - operations

    private func requireSFTP() throws -> SFTPClient {
        guard let sftp else { throw SFTPError.connectionFailed("Not connected.") }
        return sftp
    }

    public func realPath(_ path: String) async throws -> String {
        let sftp = try requireSFTP()
        do {
            return try await sftp.getRealPath(atPath: path)
        } catch {
            throw Self.mapOpError(error, path: path)
        }
    }

    public func list(path: String) async throws -> [FileEntry] {
        let sftp = try requireSFTP()
        let base = normalizeDirectory(path)
        do {
            let names = try await sftp.listDirectory(atPath: path)
            var out: [FileEntry] = []
            for name in names {
                for component in name.components {
                    let filename = component.filename
                    if filename == "." || filename == ".." { continue }
                    out.append(Self.entry(for: component, in: base))
                }
            }
            out.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return out
        } catch {
            throw Self.mapOpError(error, path: path)
        }
    }

    public func download(path: String) async throws -> Data {
        let sftp = try requireSFTP()
        do {
            return try await sftp.withFile(filePath: path, flags: .read) { file in
                let buffer = try await file.readAll()
                return Data(buffer: buffer)
            }
        } catch {
            throw Self.mapOpError(error, path: path)
        }
    }

    public func upload(path: String, data: Data) async throws {
        let sftp = try requireSFTP()
        let buffer = ByteBuffer(data: data)
        do {
            try await sftp.withFile(filePath: path, flags: [.write, .create, .truncate]) { file in
                try await file.write(buffer, at: 0)
            }
        } catch {
            throw Self.mapOpError(error, path: path)
        }
    }

    public func makeDirectory(path: String) async throws {
        let sftp = try requireSFTP()
        do {
            try await sftp.createDirectory(atPath: path)
        } catch {
            throw Self.mapOpError(error, path: path)
        }
    }

    public func rename(from: String, to: String) async throws {
        let sftp = try requireSFTP()
        do {
            try await sftp.rename(at: from, to: to)
        } catch {
            throw Self.mapOpError(error, path: from)
        }
    }

    public func remove(path: String) async throws {
        let sftp = try requireSFTP()
        do {
            try await sftp.remove(at: path)
        } catch {
            throw Self.mapOpError(error, path: path)
        }
    }

    public func removeDirectory(path: String) async throws {
        let sftp = try requireSFTP()
        do {
            try await sftp.rmdir(at: path)
        } catch {
            throw Self.mapOpError(error, path: path)
        }
    }

    // MARK: - mapping

    /// Build a `FileEntry` from a listing component, deriving directory-ness from POSIX mode bits and
    /// falling back to the `ls -l` `longname` first character when the server omits permissions.
    static func entry(for component: SFTPPathComponent, in directory: String) -> FileEntry {
        let attrs = component.attributes
        let mode = attrs.permissions
        let isDir: Bool
        if let mode {
            isDir = FileAttributes.isDirectory(mode: mode)
        } else {
            isDir = component.longname.first == "d"
        }
        let path = directory == "/" ? "/\(component.filename)" : "\(directory)/\(component.filename)"
        return FileEntry(
            name: component.filename,
            path: path,
            isDirectory: isDir,
            size: attrs.size ?? 0,
            modified: attrs.accessModificationTime?.modificationTime,
            permissions: mode)
    }

    /// Strip a trailing slash (except for root) so joined child paths never double up separators.
    private func normalizeDirectory(_ path: String) -> String {
        if path.count > 1 && path.hasSuffix("/") { return String(path.dropLast()) }
        return path
    }

    private static func mapConnectError(_ error: Error) -> SFTPError {
        let text = "\(error)"
        let lower = text.lowercased()
        if lower.contains("auth") || lower.contains("password") || lower.contains("permission denied") {
            return .auth("Authentication failed: \(text)")
        }
        if lower.contains("host key") || lower.contains("hostkey") {
            return .hostKey(text)
        }
        return .connectionFailed(text)
    }

    private static func mapOpError(_ error: Error, path: String) -> SFTPError {
        if let e = error as? SFTPError { return e }
        let text = "\(error)"
        let lower = text.lowercased()
        if lower.contains("no such file") || lower.contains("nosuchfile") || lower.contains("notfound") {
            return .notFound("Not found: \(path)")
        }
        return .connectionFailed(text)
    }
}
