// Tests/CoreChecks/SFTPECDSAKeyChecks.swift
//
// ECDSA identity-file support for the SFTP backend. These checks parse real OpenSSH ECDSA private
// keys (generated with `ssh-keygen -t ecdsa -b {256,384,521}`) into swift-crypto signing keys and
// verify the derived public key matches the corresponding `.pub` fixture — proving the parser is
// correct, not merely non-throwing. The private keys below are throwaway fixtures, safe to commit.
import Citadel
import Crypto
import Foundation
import SimpletonSFTP

func runSFTPECDSAKeyChecks(_ t: TestRunner) {
    t.suite("SSHKeyDetection recognises ECDSA private keys") {
        expectDetected(t, ECDSAKeyFixtures.p256, .ecdsaP256, "P-256")
        expectDetected(t, ECDSAKeyFixtures.p384, .ecdsaP384, "P-384")
        expectDetected(t, ECDSAKeyFixtures.p521, .ecdsaP521, "P-521")
        // The type is read from the (always plaintext) public section, so an encrypted key still
        // detects as ECDSA — the encryption is only rejected later, when parsing the private scalar.
        expectDetected(t, ECDSAKeyFixtures.p256Encrypted, .ecdsaP256, "encrypted P-256")
    }

    t.suite("OpenSSHECDSAKey.parse produces the correct P-256 key") {
        guard case .p256(let key)? = tryParse(t, ECDSAKeyFixtures.p256, "P-256") else { return }
        t.expectEqual(
            Data(key.publicKey.x963Representation).base64EncodedString(),
            ECDSAKeyFixtures.p256PublicPoint,
            "derived P-256 public point matches ssh-keygen .pub")
    }

    t.suite("OpenSSHECDSAKey.parse produces the correct P-384 key") {
        guard case .p384(let key)? = tryParse(t, ECDSAKeyFixtures.p384, "P-384") else { return }
        t.expectEqual(
            Data(key.publicKey.x963Representation).base64EncodedString(),
            ECDSAKeyFixtures.p384PublicPoint,
            "derived P-384 public point matches ssh-keygen .pub")
    }

    t.suite("OpenSSHECDSAKey.parse produces the correct P-521 key") {
        guard case .p521(let key)? = tryParse(t, ECDSAKeyFixtures.p521, "P-521") else { return }
        t.expectEqual(
            Data(key.publicKey.x963Representation).base64EncodedString(),
            ECDSAKeyFixtures.p521PublicPoint,
            "derived P-521 public point matches ssh-keygen .pub")
    }

    t.suite("Parsed ECDSA key can sign and self-verify") {
        // A round-trip sign/verify proves the scalar was reconstructed into a usable signing key.
        if case .p256(let key)? = try? OpenSSHECDSAKey.parse(pem: ECDSAKeyFixtures.p256) {
            let message = Data("simpleton-sftp".utf8)
            if let signature = try? key.signature(for: message) {
                t.expect(
                    key.publicKey.isValidSignature(signature, for: message),
                    "P-256 signature verifies against its own public key")
            } else {
                t.expect(false, "P-256 key failed to sign")
            }
        } else {
            t.expect(false, "P-256 fixture failed to parse for signing")
        }
    }

    runEncryptedECDSAKeyChecks(t)

    t.suite("OpenSSHECDSAKey.parse rejects non-ECDSA and malformed input") {
        // An ed25519 OpenSSH key is a valid container but not ECDSA.
        do {
            _ = try OpenSSHECDSAKey.parse(pem: ECDSAKeyFixtures.ed25519)
            t.expect(false, "ed25519 key should not parse as ECDSA")
        } catch let e as OpenSSHECDSAKey.ParseError {
            if case .notECDSA = e {
                t.expect(true, "ed25519 → .notECDSA")
            } else {
                t.expect(false, "wrong error for ed25519: \(e)")
            }
        } catch {
            t.expect(false, "unexpected error for ed25519: \(error)")
        }

        // Garbage that is not even a valid container.
        do {
            _ = try OpenSSHECDSAKey.parse(pem: "not a key at all")
            t.expect(false, "garbage should not parse")
        } catch let e as OpenSSHECDSAKey.ParseError {
            t.expectEqual(e, .invalidContainer, "garbage → .invalidContainer")
        } catch {
            t.expect(false, "unexpected error for garbage: \(error)")
        }
    }
}

// MARK: - Encrypted-key round-trips

/// Decrypt each bcrypt-encrypted ECDSA fixture with the right passphrase and check the derived public
/// point matches the `.pub` fixture (proving the bcrypt_pbkdf key/IV and AES decrypt are correct, not
/// merely non-throwing), then confirm a wrong passphrase is rejected as `.incorrectPassphrase`.
private func runEncryptedECDSAKeyChecks(_ t: TestRunner) {
    let pass = Array(ECDSAKeyFixtures.encryptedPassphrase.utf8)

    // (fixture, expected-public-point, label) across all three supported ciphers and two curves.
    let cases: [(String, String, String)] = [
        (ECDSAKeyFixtures.p256Encrypted, ECDSAKeyFixtures.p256EncryptedPublicPoint, "aes256-ctr P-256"),
        (ECDSAKeyFixtures.p384Encrypted, ECDSAKeyFixtures.p384EncryptedPublicPoint, "aes256-ctr P-384"),
        (ECDSAKeyFixtures.p256EncryptedCBC, ECDSAKeyFixtures.p256EncryptedCBCPublicPoint, "aes256-cbc P-256"),
        (
            ECDSAKeyFixtures.p256Encrypted128CTR, ECDSAKeyFixtures.p256Encrypted128CTRPublicPoint,
            "aes128-ctr P-256"
        ),
    ]

    t.suite("Encrypted ECDSA keys decrypt to the correct public point") {
        for (pem, expectedPoint, label) in cases {
            do {
                let parsed = try OpenSSHECDSAKey.parse(pem: pem, passphrase: pass)
                let actual = publicPointBase64(parsed)
                t.expectEqual(actual, expectedPoint, "\(label) decrypted public point")
            } catch {
                t.expect(false, "\(label) decrypt threw: \(error)")
            }
        }
    }

    t.suite("Wrong passphrase on an encrypted ECDSA key is rejected precisely") {
        do {
            _ = try OpenSSHECDSAKey.parse(
                pem: ECDSAKeyFixtures.p256Encrypted, passphrase: Array("totally-wrong".utf8))
            t.expect(false, "wrong passphrase should not decrypt")
        } catch let e as OpenSSHECDSAKey.ParseError {
            t.expectEqual(e, .incorrectPassphrase, "wrong passphrase → .incorrectPassphrase")
        } catch {
            t.expect(false, "wrong error type for wrong passphrase: \(error)")
        }
    }

    t.suite("Encrypted ECDSA key with no passphrase is rejected precisely") {
        do {
            _ = try OpenSSHECDSAKey.parse(pem: ECDSAKeyFixtures.p256Encrypted, passphrase: nil)
            t.expect(false, "missing passphrase should not decrypt")
        } catch let e as OpenSSHECDSAKey.ParseError {
            t.expectEqual(e, .passphraseRequired, "missing passphrase → .passphraseRequired")
        } catch {
            t.expect(false, "wrong error type for missing passphrase: \(error)")
        }
    }

    t.suite("Decrypted ECDSA key can sign and self-verify") {
        // A sign/verify round-trip on a decrypted key proves the scalar (not just the point) is right.
        if case .p256(let key)? = try? OpenSSHECDSAKey.parse(
            pem: ECDSAKeyFixtures.p256Encrypted, passphrase: pass)
        {
            let message = Data("simpleton-sftp-encrypted".utf8)
            if let signature = try? key.signature(for: message) {
                t.expect(
                    key.publicKey.isValidSignature(signature, for: message),
                    "decrypted P-256 signature verifies against its own public key")
            } else {
                t.expect(false, "decrypted P-256 key failed to sign")
            }
        } else {
            t.expect(false, "encrypted P-256 fixture failed to decrypt for signing")
        }
    }
}

private func publicPointBase64(_ parsed: OpenSSHECDSAKey.ParsedKey) -> String {
    switch parsed {
    case .p256(let key): return Data(key.publicKey.x963Representation).base64EncodedString()
    case .p384(let key): return Data(key.publicKey.x963Representation).base64EncodedString()
    case .p521(let key): return Data(key.publicKey.x963Representation).base64EncodedString()
    }
}

// MARK: - Helpers

private func expectDetected(
    _ t: TestRunner, _ pem: String, _ expected: SSHKeyType, _ label: String
) {
    do {
        let detected = try SSHKeyDetection.detectPrivateKeyType(from: pem)
        t.expectEqual(detected, expected, "\(label) detected as \(expected.description)")
    } catch {
        t.expect(false, "\(label) detection threw: \(error)")
    }
}

private func tryParse(
    _ t: TestRunner, _ pem: String, _ label: String
) -> OpenSSHECDSAKey.ParsedKey? {
    do {
        return try OpenSSHECDSAKey.parse(pem: pem)
    } catch {
        t.expect(false, "\(label) parse threw: \(error)")
        return nil
    }
}
