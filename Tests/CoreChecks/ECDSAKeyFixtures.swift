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

    /// A bcrypt-encrypted P-256 key (cipher `aes256-ctr`, kdf `bcrypt`). Passphrase was "secret123".
    static let p256Encrypted = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABB9QXxm1q
        1EsTLm0Cx3Liy/AAAAGAAAAAEAAABoAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlz
        dHAyNTYAAABBBMEt1MvpijNOj/D6Aceyq6ucEnya5l4nTD0hjcWe0uY/8qMVWXpWfEGCq6
        t4Ib9PcyZeuCusG1d6zyTSx2jl+SMAAACg6rPT+sucQa1sGFZYhiGvEljTlifvwvVk11bC
        pCZZcy9L5r420VofYqQxif8sUR/crxmv2uXJNXBVyyD5RkiAoaUaqQsVKr5sCZ9XM+I8QQ
        InkRlpf6YpzfO7KFIsyuoxUGO52T4/stByXsEWMM0bZf4OCUWsw5w57L7np9zmbuLtBmdH
        xh2sVsmLuJBWGYaJds0tUJiaoTAWShSbzf0O2w==
        -----END OPENSSH PRIVATE KEY-----
        """

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
