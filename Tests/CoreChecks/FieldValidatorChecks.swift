// Tests/CoreChecks/FieldValidatorChecks.swift
// Ported from Tests/SimpletonCoreTests/Core/FieldValidatorTests.swift
import SimpletonCore

func runFieldValidatorChecks(_ t: TestRunner) {
    t.suite("FieldValidator.testValidHostnames") {
        t.expect(FieldValidator.isValidHostname("example.com"), "example.com is valid")
        t.expect(FieldValidator.isValidHostname("10.0.1.5"), "10.0.1.5 is valid")
        t.expect(FieldValidator.isValidHostname("my-server.prod.internal"), "my-server.prod.internal is valid")
        t.expect(FieldValidator.isValidHostname("host_name"), "host_name is valid")
    }

    t.suite("FieldValidator.testInvalidHostnames") {
        t.expect(!FieldValidator.isValidHostname(""), "empty is invalid")
        t.expect(!FieldValidator.isValidHostname("host; rm -rf /"), "injection is invalid")
        t.expect(!FieldValidator.isValidHostname("host`whoami`"), "backtick is invalid")
        t.expect(!FieldValidator.isValidHostname("host$(cmd)"), "command substitution is invalid")
        t.expect(!FieldValidator.isValidHostname("host name"), "space is invalid")
    }

    t.suite("FieldValidator.testValidUsernames") {
        t.expect(FieldValidator.isValidUsername("deploy"), "deploy is valid")
        t.expect(FieldValidator.isValidUsername("admin_user"), "admin_user is valid")
        t.expect(FieldValidator.isValidUsername("user-name"), "user-name is valid")
        t.expect(FieldValidator.isValidUsername("user.name"), "user.name is valid")
    }

    t.suite("FieldValidator.testInvalidUsernames") {
        t.expect(!FieldValidator.isValidUsername(""), "empty is invalid")
        t.expect(!FieldValidator.isValidUsername("user; rm"), "injection is invalid")
        t.expect(!FieldValidator.isValidUsername("user name"), "space is invalid")
    }

    t.suite("FieldValidator.testValidPorts") {
        t.expect(FieldValidator.isValidPort(22), "22 is valid")
        t.expect(FieldValidator.isValidPort(1), "1 is valid")
        t.expect(FieldValidator.isValidPort(65535), "65535 is valid")
    }

    t.suite("FieldValidator.testInvalidPorts") {
        t.expect(!FieldValidator.isValidPort(0), "0 is invalid")
        t.expect(!FieldValidator.isValidPort(-1), "-1 is invalid")
        t.expect(!FieldValidator.isValidPort(65536), "65536 is invalid")
    }
}
