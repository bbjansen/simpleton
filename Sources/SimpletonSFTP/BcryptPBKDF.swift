// Sources/SimpletonSFTP/BcryptPBKDF.swift
//
// OpenSSH / OpenBSD `bcrypt_pbkdf` — the password-based key-derivation function that keys the cipher
// protecting an encrypted OpenSSH private key. A faithful Swift port of the OpenBSD reference
// `openbsd-compat/bcrypt_pbkdf.c` (Ted Unangst), built on the `Blowfish` EksBlowfish core.
//
// The construction (see the reference header comment):
//   1. The password and per-block salt are collapsed with SHA-512 (the caller-side optimisation the
//      reference notes; here we use swift-crypto's `SHA512`).
//   2. `bcrypt_hash` runs the fixed-cost EksBlowfish schedule — `expandstate` once, then 64 rounds
//      of `expand0state(salt)` + `expand0state(pass)` — and enciphers the fixed 32-byte magic string
//      "OxychromaticBlowfishSwatDynamite" 64 times, emitting 32 little-endian bytes.
//   3. PBKDF2-style outer loop: for each 32-byte output block it iterates `rounds` inner hashes,
//      re-hashing the previous output as the next salt and XOR-accumulating, then scatters the bytes
//      non-linearly (the deliberate deviation from stock PBKDF2) using `stride`/`count`.
//
// Correctness is proven byte-for-byte in CoreChecks against the published OpenBSD reference vectors
// (the same "golden" vectors Go's `x/crypto/ssh/internal/bcrypt_pbkdf` tests against) plus the inner
// `bcryptHash` vector, and end-to-end by decrypting real `ssh-keygen` fixtures.
//
// Reference: OpenSSH `openbsd-compat/bcrypt_pbkdf.c` (rev 1.17).
import Crypto
import Foundation

public enum BcryptPBKDF {
    /// `BCRYPT_HASHSIZE` — the inner hash emits exactly 32 bytes per block.
    public static let hashSize = 32

    /// Errors surfaced for invalid parameters, mirroring the reference's `bad:` bail-outs.
    public enum Failure: Error, Equatable {
        case invalidParameters
    }

    /// Derive `keyLen` bytes from `password`/`salt` over `rounds` bcrypt iterations.
    ///
    /// - Parameters:
    ///   - password: the passphrase bytes (already UTF-8 encoded by the caller).
    ///   - salt: the KDF salt from the OpenSSH `bcrypt` kdfoptions.
    ///   - keyLen: total bytes to produce (cipher key length + IV length for OpenSSH keys).
    ///   - rounds: bcrypt work factor from the kdfoptions (OpenSSH default is 16).
    /// - Returns: exactly `keyLen` derived bytes.
    public static func derive(
        password: [UInt8], salt: [UInt8], keyLen: Int, rounds: Int
    ) throws -> [UInt8] {
        // "nothing crazy" — the same guards as the reference. keyLen is bounded by sizeof(out)^2.
        guard rounds >= 1, !password.isEmpty, !salt.isEmpty, keyLen > 0,
            keyLen <= hashSize * hashSize, salt.count <= (1 << 20)
        else {
            throw Failure.invalidParameters
        }

        let origKeyLen = keyLen
        var remaining = keyLen
        var key = [UInt8](repeating: 0, count: keyLen)

        // stride / amt: how the 32-byte output blocks are scattered across the key so that every
        // subkey byte depends on the full derivation (the reference's anti-partial-computation trick).
        let stride = (keyLen + hashSize - 1) / hashSize
        var amt = (keyLen + stride - 1) / stride

        // Collapse the password once; it never changes between blocks.
        let sha2pass = Array(SHA512.hash(data: Data(password)))

        // countsalt = salt || big-endian uint32 block counter.
        var countsalt = salt
        countsalt.append(contentsOf: [0, 0, 0, 0])

        var count: UInt32 = 1
        while remaining > 0 {
            let base = salt.count
            countsalt[base + 0] = UInt8((count >> 24) & 0xff)
            countsalt[base + 1] = UInt8((count >> 16) & 0xff)
            countsalt[base + 2] = UInt8((count >> 8) & 0xff)
            countsalt[base + 3] = UInt8(count & 0xff)

            // First round: salt is the counted salt.
            var sha2salt = Array(SHA512.hash(data: Data(countsalt)))
            var tmpout = bcryptHash(sha2pass: sha2pass, sha2salt: sha2salt)
            var out = tmpout

            // Subsequent rounds: salt is the previous inner output; XOR-accumulate into `out`.
            for _ in 1..<max(rounds, 1) {
                sha2salt = Array(SHA512.hash(data: Data(tmpout)))
                tmpout = bcryptHash(sha2pass: sha2pass, sha2salt: sha2salt)
                for j in 0..<hashSize {
                    out[j] ^= tmpout[j]
                }
            }

            // Scatter this block's bytes into the key: key[i*stride + (count-1)] = out[i].
            amt = min(amt, remaining)
            var produced = 0
            for i in 0..<amt {
                let dest = i * stride + Int(count - 1)
                if dest >= origKeyLen { break }
                key[dest] = out[i]
                produced += 1
            }
            remaining -= produced
            count += 1
        }

        return key
    }

    // MARK: - Inner hash

    /// The 32-byte "bcrypt" hash of a SHA-512-collapsed password/salt pair. A faithful port of the
    /// reference `bcrypt_hash`: EksBlowfish key schedule (`expandstate` + 64 alternating
    /// `expand0state` rounds), then 64 encipherings of the fixed magic string, emitted little-endian.
    public static func bcryptHash(sha2pass: [UInt8], sha2salt: [UInt8]) -> [UInt8] {
        // The 32-byte magic constant "OxychromaticBlowfishSwatDynamite".
        let ciphertext = Array("OxychromaticBlowfishSwatDynamite".utf8)

        var state = BlowfishContext()
        Blowfish.expandState(&state, data: sha2salt, key: sha2pass)
        for _ in 0..<64 {
            Blowfish.expand0State(&state, key: sha2salt)
            Blowfish.expand0State(&state, key: sha2pass)
        }

        // Pack the 32-byte magic into 8 big-endian words (via the reference's stream2word cursor).
        var cdata = [UInt32](repeating: 0, count: 8)
        var cursor = 0
        for i in 0..<8 {
            cdata[i] = Blowfish.stream2word(ciphertext, current: &cursor)
        }

        // 64 passes of enciphering all 4 blocks (BCRYPT_WORDS / 2 = 4 blocks per pass).
        for _ in 0..<64 {
            Blowfish.blfEnc(&state, &cdata, blocks: 8 / 2)
        }

        // Emit each word little-endian, exactly as the reference `out[4*i+0..3]`.
        var out = [UInt8](repeating: 0, count: hashSize)
        for i in 0..<8 {
            out[4 * i + 0] = UInt8(cdata[i] & 0xff)
            out[4 * i + 1] = UInt8((cdata[i] >> 8) & 0xff)
            out[4 * i + 2] = UInt8((cdata[i] >> 16) & 0xff)
            out[4 * i + 3] = UInt8((cdata[i] >> 24) & 0xff)
        }
        return out
    }
}
