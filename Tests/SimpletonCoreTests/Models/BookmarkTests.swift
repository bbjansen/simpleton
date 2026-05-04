// Tests/SimpletonCoreTests/Models/BookmarkTests.swift
import XCTest
@testable import SimpletonCore

final class BookmarkTests: XCTestCase {

    func testBookmarkRoundTrip() throws {
        let bookmark = Bookmark(
            id: UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-ef1234567890")!,
            name: "web-prod-01",
            host: "10.0.1.6",
            port: 22,
            user: "deploy",
            auth: .key(identityFile: "~/.ssh/prod_ed25519"),
            jumpHosts: ["bastion-jump"],
            portForwards: [PortForward(direction: .local, localPort: 3000, remoteHost: "localhost", remotePort: 3000)],
            tags: ["prod", "web"],
            notes: "Main web server",
            pinned: true,
            sshConfigHost: nil
        )

        let data = try JSONEncoder().encode(bookmark)
        let decoded = try JSONDecoder().decode(Bookmark.self, from: data)

        XCTAssertEqual(decoded.id, bookmark.id)
        XCTAssertEqual(decoded.name, "web-prod-01")
        XCTAssertEqual(decoded.host, "10.0.1.6")
        XCTAssertEqual(decoded.port, 22)
        XCTAssertEqual(decoded.user, "deploy")
        XCTAssertEqual(decoded.tags, ["prod", "web"])
        XCTAssertEqual(decoded.pinned, true)
        XCTAssertEqual(decoded.jumpHosts, ["bastion-jump"])
        XCTAssertEqual(decoded.portForwards.count, 1)
        XCTAssertEqual(decoded.portForwards[0].localPort, 3000)
    }

    func testAuthMethodKeyRoundTrip() throws {
        let auth = AuthMethod.key(identityFile: "~/.ssh/id_ed25519")
        let data = try JSONEncoder().encode(auth)
        let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
        if case .key(let file) = decoded {
            XCTAssertEqual(file, "~/.ssh/id_ed25519")
        } else {
            XCTFail("Expected .key")
        }
    }

    func testAuthMethodPasswordRoundTrip() throws {
        let auth = AuthMethod.password
        let data = try JSONEncoder().encode(auth)
        let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
        if case .password = decoded {} else { XCTFail("Expected .password") }
    }

    func testAuthMethodAgentRoundTrip() throws {
        let auth = AuthMethod.agent
        let data = try JSONEncoder().encode(auth)
        let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
        if case .agent = decoded {} else { XCTFail("Expected .agent") }
    }

    func testAuthMethodNoneRoundTrip() throws {
        let auth = AuthMethod.none
        let data = try JSONEncoder().encode(auth)
        let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
        if case .none = decoded {} else { XCTFail("Expected .none") }
    }

    func testPortForwardDirections() throws {
        let local = PortForward(direction: .local, localPort: 8080, remoteHost: "localhost", remotePort: 80)
        let remote = PortForward(direction: .remote, localPort: 9090, remoteHost: "0.0.0.0", remotePort: 9090)

        let data = try JSONEncoder().encode([local, remote])
        let decoded = try JSONDecoder().decode([PortForward].self, from: data)

        XCTAssertEqual(decoded[0].direction, .local)
        XCTAssertEqual(decoded[1].direction, .remote)
    }

    func testBookmarkDefaultValues() {
        let bookmark = Bookmark(name: "test", host: "example.com")
        XCTAssertEqual(bookmark.port, 22)
        XCTAssertEqual(bookmark.user, nil)
        XCTAssertEqual(bookmark.auth, .agent)
        XCTAssertEqual(bookmark.jumpHosts, [])
        XCTAssertEqual(bookmark.portForwards, [])
        XCTAssertEqual(bookmark.tags, [])
        XCTAssertEqual(bookmark.notes, "")
        XCTAssertEqual(bookmark.pinned, false)
        XCTAssertNil(bookmark.sshConfigHost)
    }

    func testBookmarkFileRoundTrip() throws {
        let file = BookmarkFile(bookmarks: [
            Bookmark(name: "a", host: "1.1.1.1"),
            Bookmark(name: "b", host: "2.2.2.2"),
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(file)
        let decoded = try JSONDecoder().decode(BookmarkFile.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.bookmarks.count, 2)
        XCTAssertEqual(decoded.bookmarks[0].name, "a")
    }
}
