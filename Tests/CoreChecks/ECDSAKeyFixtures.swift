// Tests/CoreChecks/ECDSAKeyFixtures.swift
//
// Throwaway OpenSSH key fixtures for the SFTP ECDSA checks. Generated with:
//   ssh-keygen -t ecdsa -b {256,384,521} -N ""            (unencrypted)
//   ssh-keygen -t ecdsa -b 256      -N "secret123"        (bcrypt-encrypted)
//   ssh-keygen -t ed25519           -N ""                 (non-ECDSA negative case)
// These private keys are disposable test material and are safe to commit — they authenticate
// nothing real. The `*PublicPoint` values are the base64 of the uncompressed EC point (Q) taken
// straight from each `.pub` file, which is exactly swift-crypto's `x963Representation`.
enum ECDSAKeyFixtures {
    static let p256 = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
        1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQRHIlzku4ZBN0v1rcUoDGox5x8DL9du
        D2pbqvXHUXo/GhKzFHQHrvVIR4u90NAGZ4bAHOfK2ItsMyHNkc1+O4DjAAAAoIsycKmLMn
        CpAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEciXOS7hkE3S/Wt
        xSgMajHnHwMv124Paluq9cdRej8aErMUdAeu9UhHi73Q0AZnhsAc58rYi2wzIc2RzX47gO
        MAAAAgOt/j14ar5ALuGD0YpugNjLTLaRjRdegLAsflMwVmujgAAAAIcDI1NnRlc3Q=
        -----END OPENSSH PRIVATE KEY-----
        """

    static let p256PublicPoint =
        "BEciXOS7hkE3S/WtxSgMajHnHwMv124Paluq9cdRej8aErMUdAeu9UhHi73Q0AZnhsAc58rYi2wzIc2RzX47gOM="

    static let p384 = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAiAAAABNlY2RzYS
        1zaGEyLW5pc3RwMzg0AAAACG5pc3RwMzg0AAAAYQRSsd3XSXbAcvCGFB+DI3tnw81UFEmr
        E5Eiaof40os467jkqJmqjxbOCfNY2TzIQQljUVfEVDUGk4Ip6YZny88GuRaEa9mmTi4TJ6
        0/knk4Uc09H+Nv17hZizetLQznfGYAAADYFpqY6RaamOkAAAATZWNkc2Etc2hhMi1uaXN0
        cDM4NAAAAAhuaXN0cDM4NAAAAGEEUrHd10l2wHLwhhQfgyN7Z8PNVBRJqxORImqH+NKLOO
        u45KiZqo8WzgnzWNk8yEEJY1FXxFQ1BpOCKemGZ8vPBrkWhGvZpk4uEyetP5J5OFHNPR/j
        b9e4WYs3rS0M53xmAAAAMQDrgpkboT2mq598DsYtoU+t+i0juEkY54kIzh2Io50Wp3OJxo
        9kaWHq4JAl9XF06GoAAAAIcDM4NHRlc3QBAgMEBQYH
        -----END OPENSSH PRIVATE KEY-----
        """

    static let p384PublicPoint =
        "BFKx3ddJdsBy8IYUH4Mje2fDzVQUSasTkSJqh/jSizjruOSomaqPFs4J81jZPMhBCWNRV8RUNQaTginphmfLzwa5FoRr2aZOLhMnrT+SeThRzT0f42/XuFmLN60tDOd8Zg=="

    static let p521 = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAArAAAABNlY2RzYS
        1zaGEyLW5pc3RwNTIxAAAACG5pc3RwNTIxAAAAhQQBrKGnctodMDp83RtLKwZeOpoiGDgJ
        EFjcHNhJposuX8LzyJEEsu/QAJgHzBogjA1jNBDbX1dDi5jVGCNbgs/Gq5EAEv/NV0OORt
        qUh2PJ1cwd865L57R3H7Y6N10iUWlTwEI3MTnKBS92Z7yQBqyx4azdg3pxwzCNHbEOC8Yl
        /XAUJiYAAAEIndvfRZ3b30UAAAATZWNkc2Etc2hhMi1uaXN0cDUyMQAAAAhuaXN0cDUyMQ
        AAAIUEAayhp3LaHTA6fN0bSysGXjqaIhg4CRBY3BzYSaaLLl/C88iRBLLv0ACYB8waIIwN
        YzQQ219XQ4uY1RgjW4LPxquRABL/zVdDjkbalIdjydXMHfOuS+e0dx+2OjddIlFpU8BCNz
        E5ygUvdme8kAasseGs3YN6ccMwjR2xDgvGJf1wFCYmAAAAQgELAY7eRFyglaKABYB5U78J
        nYmsanXtCmGlJb9BrAU7Bikml0VpWSravNOhYuLNaP3ugdSYIJ1r80Zsaq7B/uCPPQAAAA
        hwNTIxdGVzdAEC
        -----END OPENSSH PRIVATE KEY-----
        """

    static let p521PublicPoint =
        "BAGsoady2h0wOnzdG0srBl46miIYOAkQWNwc2Emmiy5fwvPIkQSy79AAmAfMGiCMDWM0ENtfV0OLmNUYI1uCz8arkQAS/81XQ45G2pSHY8nVzB3zrkvntHcftjo3XSJRaVPAQjcxOcoFL3ZnvJAGrLHhrN2DenHDMI0dsQ4LxiX9cBQmJg=="

    /// The passphrase all `*Encrypted` fixtures below were created with (`ssh-keygen -N`).
    static let encryptedPassphrase = "sftp-enc-pass"

    /// A bcrypt-encrypted P-256 key (cipher `aes256-ctr`, kdf `bcrypt`, 16 rounds — ssh-keygen
    /// defaults). Passphrase is `encryptedPassphrase`.
    static let p256Encrypted = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABA87xbPFE
        D4osmfndZu1aUqAAAAGAAAAAEAAABoAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlz
        dHAyNTYAAABBBCNNc3Qz51Jke3d/CdA4VdKjYVxRnSYlg9qPXWLjcZEQpGkmPeLRU2x/e4
        +jNBK27wycCI1KTdg8IYarEMbrDgkAAACwXP1YEA1QmS0+X/zcqqjkiuvbCSTsV4wT1K+n
        CfXW8MPt9H2BiZ7PeajCUrO5jWuM1jmxNjcN00OpYJNGM3tNk1Z0OKfIhjR02twBe/J4sz
        sZowMm5NTsx5IEQnq6luYvF4ppaEjJ6K2ugMS9KDATOX0sDDDfk15V9KHcjz3ZJ6dmI7Hr
        PdpcJz49vRLiaQLN9WmtfaAEW+rRuVt9gkwhUeLYuWUDbYlGpIxxgaIfZi4=
        -----END OPENSSH PRIVATE KEY-----
        """

    /// The public point (uncompressed EC point Q, swift-crypto `x963Representation`) of the
    /// decrypted `p256Encrypted` key, taken from its `.pub` file.
    static let p256EncryptedPublicPoint =
        "BCNNc3Qz51Jke3d/CdA4VdKjYVxRnSYlg9qPXWLjcZEQpGkmPeLRU2x/e4+jNBK27wycCI1KTdg8IYarEMbrDgk="

    /// A bcrypt-encrypted P-384 key (cipher `aes256-ctr`). Passphrase is `encryptedPassphrase`.
    static let p384Encrypted = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABCnksGcD6
        9AQEX4si1aGCnqAAAAGAAAAAEAAACIAAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlz
        dHAzODQAAABhBGrrcwJrdowtHgJRyVDguQnODaf2hgifr8Rht2dUWKuNXbN3y16R9wVCxY
        DwxzVpvRoq/sCY99Bv46PpdLIAXGyw48DlpjqmqZ3h+8iAtHiYgJoynCyXVPubKX416CtZ
        eQAAAOD4Y03D6Pj/Rk6E/cv/DuBGXEh3OU+kqNTB1lm78M7Ee9QaNv+Qj9rLdH/xuxGUQx
        2+DVoJgR27GSOir5dkiv5BDxrLrjejcEdmfEzbwIwXiHv3DUw71Gk5W6GEJn5M9YhJYaRl
        uRyHwgO7WgSgGFkrFNn06P7BfMO83K47O7h/v+QqzJ1V5evSFj+haztGWHWxBuMCCiIH5e
        i5I8ipGRIQj47drUyJ6E7dMtJzI1vMZsrVhIKwXA+IlLuaPIYVQY0+12Uof/nZyozzo2ZF
        UVsbCddHTokzNyOhWts42OpZTA==
        -----END OPENSSH PRIVATE KEY-----
        """

    static let p384EncryptedPublicPoint =
        "BGrrcwJrdowtHgJRyVDguQnODaf2hgifr8Rht2dUWKuNXbN3y16R9wVCxYDwxzVpvRoq/sCY99Bv46PpdLIAXGyw48DlpjqmqZ3h+8iAtHiYgJoynCyXVPubKX416CtZeQ=="

    /// A bcrypt-encrypted P-256 key using cipher `aes256-cbc` (not the default). Passphrase is
    /// `encryptedPassphrase`. Exercises the CBC decryption path.
    static let p256EncryptedCBC = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jYmMAAAAGYmNyeXB0AAAAGAAAABBaDfq2OW
        4mB7EMWbGUDROpAAAAGAAAAAEAAABoAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlz
        dHAyNTYAAABBBCNHbFDwp+R4TTkuyeCUE/wbhkQiyMl042GWDV/mYSmfDDe99yiZ9suSPU
        G0AOn6uH3+fD/8qKl0pn40tJf4NOkAAACwh3QsqAXU6voEsglmOjis2KaUfEjCcVF1Iqbr
        WiJyRHw1fFs6m8dtM+rwCbaPnzVH6lUUYa59UuxCCm3pehKvKohBK5csVl1+4//iyYbWUJ
        Kw/xtv9RLL8QV4B5NXGkoZMTRyJPaJ/P+45cyf3Q8CEJ5wqfivxRl/KTbzZqZItNYCc9eQ
        Dgg1zUrx2CcsxZx5rfP+q4haXomtsRkWLY9tsV+MKsU89qpqmTAfmq1gkLQ=
        -----END OPENSSH PRIVATE KEY-----
        """

    static let p256EncryptedCBCPublicPoint =
        "BCNHbFDwp+R4TTkuyeCUE/wbhkQiyMl042GWDV/mYSmfDDe99yiZ9suSPUG0AOn6uH3+fD/8qKl0pn40tJf4NOk="

    /// A bcrypt-encrypted P-256 key using cipher `aes128-ctr`. Passphrase is `encryptedPassphrase`.
    /// Exercises the 128-bit CTR decryption path.
    static let p256Encrypted128CTR = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczEyOC1jdHIAAAAGYmNyeXB0AAAAGAAAABCdzyPhRK
        UH7RCxmKZqoiLEAAAAGAAAAAEAAABoAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlz
        dHAyNTYAAABBBBdM4kTRhuWC7v4phzvl1l0YRMhm+oh1yufBUqVNWJPF+VQho8s0sSiwqR
        P8xRah5heHmS/R5En1OGBllVpdxeUAAACwcvAwhup95Cozz7/s2Vq1Lph2h2O/+0aqRt9X
        gvD2nd5v+aG5oUn7v5mwy0oJcagNiw2qQKnvfpc8/3pK/lIR795G7PnrThxlcIsmaPvj+d
        NmwzfIQ/abbHNlrm9oBRXnX/a8b4vkfLAkBnXkA83MhKy4nRkoZJv9rrBVtjmGNX8apSDg
        tLD9In/FaPWdlIO/xIXCOtY//3mf9H0E+WycTtKgaHqCEgf+ZldSPgqKVmg=
        -----END OPENSSH PRIVATE KEY-----
        """

    static let p256Encrypted128CTRPublicPoint =
        "BBdM4kTRhuWC7v4phzvl1l0YRMhm+oh1yufBUqVNWJPF+VQho8s0sSiwqRP8xRah5heHmS/R5En1OGBllVpdxeU="

    /// A non-ECDSA (ed25519) OpenSSH key: a valid container, but the parser must reject it as ECDSA.
    static let ed25519 = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACBcD+XiOZw+EQZcSnTmi4YqaXJeB5WHq4e22D49wj1DngAAAJAzvZw2M72c
        NgAAAAtzc2gtZWQyNTUxOQAAACBcD+XiOZw+EQZcSnTmi4YqaXJeB5WHq4e22D49wj1Dng
        AAAEDIGbpc86ll/jACFTOe8iKIPg26+bbGyHN04iADxlqnxlwP5eI5nD4RBlxKdOaLhipp
        cl4HlYerh7bYPj3CPUOeAAAABmVkdGVzdAECAwQFBgc=
        -----END OPENSSH PRIVATE KEY-----
        """
}
