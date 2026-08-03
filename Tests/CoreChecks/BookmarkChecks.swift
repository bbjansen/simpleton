// Tests/CoreChecks/BookmarkChecks.swift
// Ported from Tests/SimpletonCoreTests/Models/BookmarkTests.swift
import Foundation
import SimpletonCore

func runBookmarkChecks(_ t: TestRunner) {
    t.suite("Bookmark.testBookmarkRoundTrip") {
        do {
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

            t.expectEqual(decoded.id, bookmark.id, "id")
            t.expectEqual(decoded.name, "web-prod-01", "name")
            t.expectEqual(decoded.host, "10.0.1.6", "host")
            t.expectEqual(decoded.port, 22, "port")
            t.expectEqual(decoded.user, "deploy", "user")
            t.expectEqual(decoded.tags, ["prod", "web"], "tags")
            t.expectEqual(decoded.pinned, true, "pinned")
            t.expectEqual(decoded.jumpHosts, ["bastion-jump"], "jumpHosts")
            t.expectEqual(decoded.portForwards.count, 1, "portForwards count")
            t.expectEqual(decoded.portForwards.first?.localPort, 3000, "portForward localPort")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("Bookmark.testAuthMethodKeyRoundTrip") {
        do {
            let auth = AuthMethod.key(identityFile: "~/.ssh/id_ed25519")
            let data = try JSONEncoder().encode(auth)
            let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
            if case .key(let file) = decoded {
                t.expectEqual(file, "~/.ssh/id_ed25519", "key file")
            } else {
                t.expect(false, "Expected .key")
            }
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("Bookmark.testAuthMethodPasswordRoundTrip") {
        do {
            let auth = AuthMethod.password
            let data = try JSONEncoder().encode(auth)
            let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
            if case .password = decoded { t.expect(true, "") } else { t.expect(false, "Expected .password") }
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("Bookmark.testAuthMethodAgentRoundTrip") {
        do {
            let auth = AuthMethod.agent
            let data = try JSONEncoder().encode(auth)
            let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
            if case .agent = decoded { t.expect(true, "") } else { t.expect(false, "Expected .agent") }
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("Bookmark.testAuthMethodNoneRoundTrip") {
        do {
            let auth = AuthMethod.none
            let data = try JSONEncoder().encode(auth)
            let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
            if case .none = decoded { t.expect(true, "") } else { t.expect(false, "Expected .none") }
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("Bookmark.testPortForwardDirections") {
        do {
            let local = PortForward(direction: .local, localPort: 8080, remoteHost: "localhost", remotePort: 80)
            let remote = PortForward(direction: .remote, localPort: 9090, remoteHost: "0.0.0.0", remotePort: 9090)
            let data = try JSONEncoder().encode([local, remote])
            let decoded = try JSONDecoder().decode([PortForward].self, from: data)
            t.expectEqual(decoded[0].direction, .local, "first direction")
            t.expectEqual(decoded[1].direction, .remote, "second direction")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("Bookmark.testBookmarkDefaultValues") {
        let bookmark = Bookmark(name: "test", host: "example.com")
        t.expectEqual(bookmark.port, 22, "default port")
        t.expect(bookmark.user == nil, "default user is nil")
        t.expectEqual(bookmark.auth, .agent, "default auth is agent")
        t.expectEqual(bookmark.jumpHosts, [], "default jumpHosts empty")
        t.expectEqual(bookmark.portForwards, [], "default portForwards empty")
        t.expectEqual(bookmark.tags, [], "default tags empty")
        t.expectEqual(bookmark.notes, "", "default notes empty")
        t.expectEqual(bookmark.pinned, false, "default pinned false")
        t.expect(bookmark.sshConfigHost == nil, "default sshConfigHost nil")
    }

    t.suite("Bookmark.testBookmarkFileRoundTrip") {
        do {
            let file = BookmarkFile(bookmarks: [
                Bookmark(name: "a", host: "1.1.1.1"),
                Bookmark(name: "b", host: "2.2.2.2"),
            ])
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(file)
            let decoded = try JSONDecoder().decode(BookmarkFile.self, from: data)
            t.expectEqual(decoded.version, 1, "version")
            t.expectEqual(decoded.bookmarks.count, 2, "bookmark count")
            t.expectEqual(decoded.bookmarks.first?.name, "a", "first bookmark name")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
