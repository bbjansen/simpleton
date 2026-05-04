// Tests/SimpletonCoreTests/Core/SSHConfigParserTests.swift
import XCTest
@testable import SimpletonCore

final class SSHConfigParserTests: XCTestCase {

    func testParseBasicHost() throws {
        let config = """
        Host myserver
            HostName 10.0.1.5
            User deploy
            Port 2222
            IdentityFile ~/.ssh/id_ed25519
        """
        let entries = SSHConfigParser.parse(content: config)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].hostAlias, "myserver")
        XCTAssertEqual(entries[0].hostname, "10.0.1.5")
        XCTAssertEqual(entries[0].user, "deploy")
        XCTAssertEqual(entries[0].port, 2222)
        XCTAssertEqual(entries[0].identityFile, "~/.ssh/id_ed25519")
        XCTAssertTrue(entries[0].isConcrete)
    }

    func testParseMultipleHosts() throws {
        let config = """
        Host server1
            HostName 10.0.1.1

        Host server2
            HostName 10.0.1.2
            User admin
        """
        let entries = SSHConfigParser.parse(content: config)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].hostAlias, "server1")
        XCTAssertEqual(entries[1].hostAlias, "server2")
        XCTAssertEqual(entries[1].user, "admin")
    }

    func testParseProxyJump() throws {
        let config = """
        Host target
            HostName 10.0.2.5
            ProxyJump bastion1,bastion2
        """
        let entries = SSHConfigParser.parse(content: config)
        XCTAssertEqual(entries[0].proxyJump, ["bastion1", "bastion2"])
    }

    func testWildcardHostIsNotConcrete() {
        let config = """
        Host *.example.com
            User deploy

        Host 10.0.*
            User admin
        """
        let entries = SSHConfigParser.parse(content: config)
        XCTAssertEqual(entries.count, 2)
        XCTAssertFalse(entries[0].isConcrete)
        XCTAssertFalse(entries[1].isConcrete)
    }

    func testParseDefaultPort() {
        let config = """
        Host myhost
            HostName example.com
        """
        let entries = SSHConfigParser.parse(content: config)
        XCTAssertEqual(entries[0].port, 22)
    }

    func testParseLocalForward() {
        let config = """
        Host myhost
            HostName example.com
            LocalForward 8080 localhost:80
            LocalForward 3000 127.0.0.1:3000
        """
        let entries = SSHConfigParser.parse(content: config)
        XCTAssertEqual(entries[0].localForwards.count, 2)
        XCTAssertEqual(entries[0].localForwards[0].localPort, 8080)
        XCTAssertEqual(entries[0].localForwards[0].remoteHost, "localhost")
        XCTAssertEqual(entries[0].localForwards[0].remotePort, 80)
    }

    func testSkipGlobalWildcard() {
        let config = """
        Host *
            ServerAliveInterval 60

        Host myhost
            HostName example.com
        """
        let entries = SSHConfigParser.parse(content: config)
        // Host * is a global config, not a connectable entry
        let concrete = entries.filter(\.isConcrete)
        XCTAssertEqual(concrete.count, 1)
        XCTAssertEqual(concrete[0].hostAlias, "myhost")
    }

    func testConvertToBookmark() {
        let entry = SSHConfigEntry(
            hostAlias: "prod-web",
            hostname: "10.0.1.6",
            user: "deploy",
            port: 22,
            identityFile: "~/.ssh/prod_key",
            proxyJump: ["bastion"],
            localForwards: [SSHForward(localPort: 3000, remoteHost: "localhost", remotePort: 3000)],
            isConcrete: true
        )
        let bookmark = entry.toBookmark()
        XCTAssertEqual(bookmark.name, "prod-web")
        XCTAssertEqual(bookmark.host, "10.0.1.6")
        XCTAssertEqual(bookmark.user, "deploy")
        XCTAssertEqual(bookmark.jumpHosts, ["bastion"])
        XCTAssertEqual(bookmark.sshConfigHost, "prod-web")
        if case .key(let file) = bookmark.auth {
            XCTAssertEqual(file, "~/.ssh/prod_key")
        } else { XCTFail("Expected .key auth") }
    }

    func testEmptyConfig() {
        let entries = SSHConfigParser.parse(content: "")
        XCTAssertTrue(entries.isEmpty)
    }

    func testCommentsIgnored() {
        let config = """
        # This is a comment
        Host myhost
            # Another comment
            HostName example.com
        """
        let entries = SSHConfigParser.parse(content: config)
        XCTAssertEqual(entries.count, 1)
    }
}
