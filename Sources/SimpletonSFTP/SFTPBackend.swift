// Sources/SimpletonSFTP/SFTPBackend.swift
import Foundation

/// The backend-agnostic interface every SFTP implementation provides. All I/O is async and runs off
/// the main actor; backends map every failure to `SFTPError` so no raw engine error escapes. Mirrors
/// the shape of `SQLDriver` in `SimpletonSQL`.
public protocol SFTPBackend: AnyObject, Sendable {
    /// Open the SSH transport (with host-key verification) and the SFTP subsystem.
    func connect() async throws
    /// List the entries of a remote directory.
    func list(path: String) async throws -> [FileEntry]
    /// Resolve a path to its canonical absolute form (e.g. "." → the login home directory).
    func realPath(_ path: String) async throws -> String
    /// Read a whole remote file into memory.
    func download(path: String) async throws -> Data
    /// Write `data` to a remote path, creating or truncating the file.
    func upload(path: String, data: Data) async throws
    /// Create a remote directory.
    func makeDirectory(path: String) async throws
    /// Rename (move) a remote file or directory.
    func rename(from: String, to: String) async throws
    /// Remove a remote file.
    func remove(path: String) async throws
    /// Remove a remote (empty) directory.
    func removeDirectory(path: String) async throws
    /// Close the SFTP subsystem and the SSH transport.
    func close() async
}

/// One entry in a remote directory listing. Pure value type, safe to hand to the main-actor UI.
public struct FileEntry: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: UInt64
    public let modified: Date?
    /// POSIX mode bits (permissions + type), or nil if the server omitted them.
    public let permissions: UInt32?

    public init(
        name: String, path: String, isDirectory: Bool, size: UInt64, modified: Date? = nil,
        permissions: UInt32? = nil
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.permissions = permissions
    }
}

/// A normalized, engine-independent view of a remote file's attributes.
public struct FileAttributes: Sendable, Hashable {
    public let size: UInt64
    public let isDirectory: Bool
    public let modified: Date?
    public let permissions: UInt32?

    public init(size: UInt64, isDirectory: Bool, modified: Date? = nil, permissions: UInt32? = nil) {
        self.size = size
        self.isDirectory = isDirectory
        self.modified = modified
        self.permissions = permissions
    }

    // POSIX S_IFMT file-type masks (values are stable across platforms).
    static let typeMask: UInt32 = 0o170000
    static let directoryType: UInt32 = 0o040000
    static let regularType: UInt32 = 0o100000
    static let symlinkType: UInt32 = 0o120000

    /// Decide whether a mode word denotes a directory. When the server omits permissions,
    /// `longname` (an `ls -l` line beginning with `d`) is used as a fallback by the caller.
    public static func isDirectory(mode: UInt32?) -> Bool {
        guard let mode else { return false }
        return (mode & typeMask) == directoryType
    }

    public static func isSymlink(mode: UInt32?) -> Bool {
        guard let mode else { return false }
        return (mode & typeMask) == symlinkType
    }
}

/// The single error type every SFTP backend surfaces. Raw engine errors are mapped into one of these
/// so the panel never has to reason about NIO/Citadel internals.
public enum SFTPError: Error, Sendable, Equatable {
    /// Authentication was rejected (bad password / key / passphrase).
    case auth(String)
    /// The server's host key is unknown-and-untrusted, or changed from a previously trusted key.
    case hostKey(String)
    /// A path was not found on the server.
    case notFound(String)
    /// The transport could not be established, or an operation failed at the protocol level.
    case connectionFailed(String)
    /// The connection kind is not an SFTP connection (factory rejection).
    case unsupported(String)

    public var message: String {
        switch self {
        case .auth(let m), .hostKey(let m), .notFound(let m), .connectionFailed(let m),
            .unsupported(let m):
            return m
        }
    }
}
