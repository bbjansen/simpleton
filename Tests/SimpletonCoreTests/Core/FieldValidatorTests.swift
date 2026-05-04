// Tests/SimpletonCoreTests/Core/FieldValidatorTests.swift
import XCTest
@testable import SimpletonCore

final class FieldValidatorTests: XCTestCase {

    func testValidHostnames() {
        XCTAssertTrue(FieldValidator.isValidHostname("example.com"))
        XCTAssertTrue(FieldValidator.isValidHostname("10.0.1.5"))
        XCTAssertTrue(FieldValidator.isValidHostname("my-server.prod.internal"))
        XCTAssertTrue(FieldValidator.isValidHostname("host_name"))
    }

    func testInvalidHostnames() {
        XCTAssertFalse(FieldValidator.isValidHostname(""))
        XCTAssertFalse(FieldValidator.isValidHostname("host; rm -rf /"))
        XCTAssertFalse(FieldValidator.isValidHostname("host`whoami`"))
        XCTAssertFalse(FieldValidator.isValidHostname("host$(cmd)"))
        XCTAssertFalse(FieldValidator.isValidHostname("host name"))
    }

    func testValidUsernames() {
        XCTAssertTrue(FieldValidator.isValidUsername("deploy"))
        XCTAssertTrue(FieldValidator.isValidUsername("admin_user"))
        XCTAssertTrue(FieldValidator.isValidUsername("user-name"))
        XCTAssertTrue(FieldValidator.isValidUsername("user.name"))
    }

    func testInvalidUsernames() {
        XCTAssertFalse(FieldValidator.isValidUsername(""))
        XCTAssertFalse(FieldValidator.isValidUsername("user; rm"))
        XCTAssertFalse(FieldValidator.isValidUsername("user name"))
    }

    func testValidPorts() {
        XCTAssertTrue(FieldValidator.isValidPort(22))
        XCTAssertTrue(FieldValidator.isValidPort(1))
        XCTAssertTrue(FieldValidator.isValidPort(65535))
    }

    func testInvalidPorts() {
        XCTAssertFalse(FieldValidator.isValidPort(0))
        XCTAssertFalse(FieldValidator.isValidPort(-1))
        XCTAssertFalse(FieldValidator.isValidPort(65536))
    }
}
