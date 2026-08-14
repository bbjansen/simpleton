// Sources/SimpletonSFTP/OpenSSHCipher.swift
//
// Symmetric decryption of the OpenSSH private-key section, keyed by `bcrypt_pbkdf`. OpenSSH encrypts
// the private section with an AES cipher named in the key header; this decrypts the three ciphers a
// current `ssh-keygen` can emit for a private key:
//
//   * `aes256-ctr`  — the OpenSSH default (32-byte key, 16-byte IV, CTR mode, no padding)
//   * `aes128-ctr`  — (16-byte key, 16-byte IV, CTR mode)
//   * `aes256-cbc`  — (32-byte key, 16-byte IV, CBC mode; the whole section is a block multiple)
//
// AES itself comes from the platform CommonCrypto (`CCCrypt` / `CCCryptorCreateWithMode`), so we do
// not re-implement the cipher — only the key/IV derivation (`bcrypt_pbkdf`) and the OpenSSH framing
// are ours. CTR is a stream cipher (decrypt == same keystream XOR), and CBC needs no un-padding here
// because OpenSSH's own trailing 1,2,3,… pad is validated by the caller, not stripped by the cipher.
//
// Reference: OpenSSH `cipher.c` (the `aes*-{ctr,cbc}` entries) and `sshkey.c` private-key framing.
import CommonCrypto
import Foundation

/// The AES ciphers used to protect OpenSSH private keys, with their OpenSSH key/IV/block sizes.
public enum OpenSSHCipher: String {
    case aes256ctr = "aes256-ctr"
    case aes128ctr = "aes128-ctr"
    case aes256cbc = "aes256-cbc"

    /// AES key length in bytes.
    public var keyLength: Int {
        switch self {
        case .aes256ctr, .aes256cbc: return 32
        case .aes128ctr: return 16
        }
    }

    /// IV length in bytes (one AES block for every cipher here).
    public var ivLength: Int { 16 }

    /// AES block size in bytes; the encrypted private section must be a whole multiple of this.
    public var blockSize: Int { 16 }

    /// Whether this cipher runs in CBC mode (vs. CTR).
    private var isCBC: Bool { self == .aes256cbc }

    public enum Failure: Error, Equatable {
        /// The ciphertext length was not a whole number of cipher blocks.
        case badLength
        /// CommonCrypto reported a failure creating or running the cryptor.
        case cryptoError(Int32)
    }

    /// Decrypt `ciphertext` with the given `key` and `iv` (both already sized for this cipher).
    ///
    /// - Throws: `Failure.badLength` for a non-block-multiple input, or `Failure.cryptoError` if
    ///   CommonCrypto fails.
    public func decrypt(_ ciphertext: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        guard ciphertext.count % blockSize == 0 else { throw Failure.badLength }
        precondition(key.count == keyLength && iv.count == ivLength, "key/iv sized by the caller")
        return isCBC
            ? try decryptCBC(ciphertext, key: key, iv: iv)
            : try decryptCTR(ciphertext, key: key, iv: iv)
    }

    // MARK: - CTR

    /// AES-CTR decryption. CTR is symmetric, so CommonCrypto's *encrypt* op with the same key/counter
    /// reproduces the keystream and recovers the plaintext. Uses the mode-based cryptor API so we can
    /// request `kCCModeCTR` explicitly (the one-shot `CCCrypt` only exposes ECB/CBC).
    private func decryptCTR(_ ciphertext: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        var cryptorRef: CCCryptorRef?
        let createStatus = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivPtr.baseAddress,
                    keyPtr.baseAddress,
                    key.count,
                    nil,
                    0,
                    0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptorRef)
            }
        }
        guard createStatus == kCCSuccess, let cryptor = cryptorRef else {
            throw Failure.cryptoError(createStatus)
        }
        defer { CCCryptorRelease(cryptor) }

        var output = [UInt8](repeating: 0, count: ciphertext.count)
        let outputCapacity = output.count
        var moved = 0
        let updateStatus = ciphertext.withUnsafeBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                CCCryptorUpdate(
                    cryptor,
                    inPtr.baseAddress,
                    ciphertext.count,
                    outPtr.baseAddress,
                    outputCapacity,
                    &moved)
            }
        }
        guard updateStatus == kCCSuccess else { throw Failure.cryptoError(updateStatus) }
        // CTR is a stream cipher: `CCCryptorFinal` produces no extra bytes, so `moved` is the total.
        return output
    }

    // MARK: - CBC

    /// AES-CBC decryption with no padding (OpenSSH's own 1,2,3,… pad is validated by the caller).
    private func decryptCBC(_ ciphertext: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: ciphertext.count)
        let outputCapacity = output.count
        var moved = 0
        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                ciphertext.withUnsafeBytes { inPtr in
                    output.withUnsafeMutableBytes { outPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),  // no kCCOptionPKCS7Padding: raw CBC, no un-padding
                            keyPtr.baseAddress,
                            key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress,
                            ciphertext.count,
                            outPtr.baseAddress,
                            outputCapacity,
                            &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.cryptoError(status) }
        return output
    }
}
