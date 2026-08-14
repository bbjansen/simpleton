// Sources/SimpletonSFTP/OpenSSHECDSAKey.swift
import Crypto
import Foundation

/// Parses an OpenSSH-format ECDSA private key (`-----BEGIN OPENSSH PRIVATE KEY-----`) into a
/// swift-crypto `P256`/`P384`/`P521` signing key.
///
/// Citadel 0.12.1 can *authenticate* with ECDSA keys — `SSHAuthenticationMethod.p256/.p384/.p521`
/// wrap swift-nio-ssh's native ECDSA signing — but its OpenSSH private-key parser only understands
/// `ssh-ed25519` and `ssh-rsa` (its internal `OpenSSH.KeyType` enum has no `ecdsa-sha2-*` cases).
/// This type fills that single gap: it decodes the OpenSSH v1 container, extracts the private scalar
/// from the `ecdsa-sha2-nistp{256,384,521}` key blob, and builds the swift-crypto key that Citadel's
/// ECDSA auth factories accept.
///
/// The OpenSSH private-key binary layout is:
///   "openssh-key-v1\0"
///   string  ciphername      (e.g. "none" or "aes256-ctr")
///   string  kdfname         (e.g. "none" or "bcrypt")
///   string  kdfoptions
///   uint32  number of keys  (always 1 for a normal key)
///   string  publickey blob
///   string  encrypted/plaintext private section, which after the two check-ints is:
///     string keytype        (e.g. "ecdsa-sha2-nistp256")
///     string curve name     (e.g. "nistp256")
///     string Q              (public EC point, ignored here)
///     mpint  d              (private scalar)
///     string comment
///     padding 1,2,3,…
///
/// Reference: <https://dnaeon.github.io/openssh-private-key-binary-format/> and RFC 4251 §5 (mpint).
public enum OpenSSHECDSAKey {
    /// A parsed ECDSA signing key, tagged with its curve so the caller can pick the right auth factory.
    public enum ParsedKey {
        case p256(P256.Signing.PrivateKey)
        case p384(P384.Signing.PrivateKey)
        case p521(P521.Signing.PrivateKey)
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        /// The PEM boundary or base64 payload was malformed.
        case invalidContainer
        /// The `openssh-key-v1` magic was missing.
        case invalidMagic
        /// A length-prefixed field ran past the end of the buffer.
        case truncated
        /// The key blob was not an `ecdsa-sha2-nistp{256,384,521}` key.
        case notECDSA(String)
        /// The key is passphrase-encrypted; the OpenSSH bcrypt KDF is not available to this backend.
        case encryptedUnsupported
        /// The private scalar could not be turned into a valid curve key.
        case invalidScalar

        public var description: String {
            switch self {
            case .invalidContainer: return "malformed OpenSSH private-key container"
            case .invalidMagic: return "missing openssh-key-v1 magic"
            case .truncated: return "truncated OpenSSH private-key data"
            case .notECDSA(let type): return "not an ECDSA key (found \(type))"
            case .encryptedUnsupported: return "passphrase-encrypted ECDSA key is not supported"
            case .invalidScalar: return "invalid ECDSA private scalar"
            }
        }
    }

    /// Parse an unencrypted OpenSSH ECDSA private key string into a swift-crypto signing key.
    ///
    /// - Throws: `ParseError.encryptedUnsupported` when the key is passphrase-protected (the OpenSSH
    ///   `bcrypt` KDF has no public API in the crypto stack available to this backend), or another
    ///   `ParseError` when the container is malformed or not ECDSA.
    public static func parse(pem: String) throws -> ParsedKey {
        let data = try decodeContainer(pem)
        var reader = SSHReader(data)

        // Magic: "openssh-key-v1\0"
        let magic = Array("openssh-key-v1".utf8) + [0x00]
        guard reader.readRaw(magic.count) == ArraySlice(magic) else { throw ParseError.invalidMagic }

        // cipher, kdf, kdfoptions
        guard let cipherName = reader.readString(),
            let kdfName = reader.readString(),
            reader.readLengthPrefixed() != nil
        else { throw ParseError.truncated }

        // Passphrase-encrypted keys use a non-"none" cipher and the "bcrypt" KDF. Decrypting those
        // requires OpenSSH's bcrypt_pbkdf, which is not exposed by swift-crypto or Citadel's public
        // API, so we surface a precise error rather than fail obscurely later.
        guard cipherName == "none", kdfName == "none" else { throw ParseError.encryptedUnsupported }

        // number of keys (expect 1), then the public-key blob (skipped), then the private section.
        guard let numberOfKeys = reader.readUInt32(), numberOfKeys == 1 else { throw ParseError.truncated }
        guard reader.readLengthPrefixed() != nil else { throw ParseError.truncated }
        guard let privateSection = reader.readLengthPrefixed() else { throw ParseError.truncated }

        var priv = SSHReader(Data(privateSection))

        // Two check integers must match on an unencrypted key; skip them (still bounds-checked).
        guard priv.readUInt32() != nil, priv.readUInt32() != nil else { throw ParseError.truncated }

        guard let keyType = priv.readString() else { throw ParseError.truncated }
        guard let curve = Curve(keyTypeName: keyType) else { throw ParseError.notECDSA(keyType) }

        // curve name (redundant with keyType) and the public point Q — both skipped.
        guard priv.readLengthPrefixed() != nil, priv.readLengthPrefixed() != nil else {
            throw ParseError.truncated
        }

        // The private scalar d, stored as an SSH mpint (big-endian, two's complement).
        guard let mpint = priv.readLengthPrefixed() else { throw ParseError.truncated }
        let scalar = normalizeScalar(Array(mpint), byteCount: curve.coordinateByteCount)

        do {
            switch curve {
            case .p256: return .p256(try P256.Signing.PrivateKey(rawRepresentation: scalar))
            case .p384: return .p384(try P384.Signing.PrivateKey(rawRepresentation: scalar))
            case .p521: return .p521(try P521.Signing.PrivateKey(rawRepresentation: scalar))
            }
        } catch {
            throw ParseError.invalidScalar
        }
    }

    // MARK: - Helpers

    /// The three NIST curves OpenSSH ECDSA keys can use, with their fixed scalar byte lengths.
    enum Curve {
        case p256, p384, p521

        init?(keyTypeName: String) {
            switch keyTypeName {
            case "ecdsa-sha2-nistp256": self = .p256
            case "ecdsa-sha2-nistp384": self = .p384
            case "ecdsa-sha2-nistp521": self = .p521
            default: return nil
            }
        }

        /// Exact scalar length swift-crypto's `init(rawRepresentation:)` requires for this curve.
        var coordinateByteCount: Int {
            switch self {
            case .p256: return 32
            case .p384: return 48
            case .p521: return 66
            }
        }
    }

    /// Strip the base64 body out of the PEM boundary and decode it.
    private static func decodeContainer(_ pem: String) throws -> Data {
        let begin = "-----BEGIN OPENSSH PRIVATE KEY-----"
        let end = "-----END OPENSSH PRIVATE KEY-----"
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(begin), trimmed.hasSuffix(end) else { throw ParseError.invalidContainer }

        let body =
            trimmed
            .replacingOccurrences(of: begin, with: "")
            .replacingOccurrences(of: end, with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let data = Data(base64Encoded: body) else { throw ParseError.invalidContainer }
        return data
    }

    /// Convert an SSH `mpint` scalar to the exact fixed width the curve expects: drop any leading
    /// sign byte (0x00 added when the high bit is set) and left-pad with zeros.
    private static func normalizeScalar(_ mpint: [UInt8], byteCount: Int) -> [UInt8] {
        var bytes = mpint
        while bytes.count > byteCount, bytes.first == 0x00 { bytes.removeFirst() }
        if bytes.count < byteCount { bytes = Array(repeating: 0x00, count: byteCount - bytes.count) + bytes }
        return bytes
    }
}

/// A tiny, bounds-checked reader for the SSH wire format (RFC 4251): 32-bit big-endian length prefix
/// followed by that many bytes. Every read returns `nil` (never traps) when the buffer is too short.
private struct SSHReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) { self.bytes = Array(data) }

    mutating func readUInt32() -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        let value =
            (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        offset += 4
        return value
    }

    mutating func readRaw(_ count: Int) -> ArraySlice<UInt8>? {
        guard offset + count <= bytes.count else { return nil }
        defer { offset += count }
        return bytes[offset..<(offset + count)]
    }

    /// Read a length-prefixed byte string (SSH `string` / `mpint`).
    mutating func readLengthPrefixed() -> ArraySlice<UInt8>? {
        guard let length = readUInt32() else { return nil }
        return readRaw(Int(length))
    }

    /// Read a length-prefixed UTF-8 string.
    mutating func readString() -> String? {
        guard let slice = readLengthPrefixed() else { return nil }
        return String(bytes: slice, encoding: .utf8)
    }
}
