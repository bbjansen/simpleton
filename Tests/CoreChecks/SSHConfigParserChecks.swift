// Tests/CoreChecks/SSHConfigParserChecks.swift
// Ported from Tests/SimpletonCoreTests/Core/SSHConfigParserTests.swift
import SimpletonCore

func runSSHConfigParserChecks(_ t: TestRunner) {
    t.suite("SSHConfigParser.testParseBasicHost") {
        let config = """
        Host myserver
            HostName 10.0.1.5
            User deploy
            Port 2222
            IdentityFile ~/.ssh/id_ed25519
        """
        let entries = SSHConfigParser.parse(content: config)
        t.expectEqual(entries.count, 1, "one entry parsed")
        if let e = entries.first {
            t.expectEqual(e.hostAlias, "myserver", "hostAlias")
            t.expectEqual(e.hostname, "10.0.1.5", "hostname")
            t.expectEqual(e.user, "deploy", "user")
            t.expectEqual(e.port, 2222, "port")
            t.expectEqual(e.identityFile, "~/.ssh/id_ed25519", "identityFile")
            t.expect(e.isConcrete, "concrete host")
        }
    }

    t.suite("SSHConfigParser.testParseMultipleHosts") {
        let config = """
        Host server1
            HostName 10.0.1.1

        Host server2
            HostName 10.0.1.2
            User admin
        """
        let entries = SSHConfigParser.parse(content: config)
        t.expectEqual(entries.count, 2, "two entries parsed")
        if entries.count == 2 {
            t.expectEqual(entries[0].hostAlias, "server1", "first hostAlias")
            t.expectEqual(entries[1].hostAlias, "server2", "second hostAlias")
            t.expectEqual(entries[1].user, "admin", "second user")
        }
    }

    t.suite("SSHConfigParser.testParseProxyJump") {
        let config = """
        Host target
            HostName 10.0.2.5
            ProxyJump bastion1,bastion2
        """
        let entries = SSHConfigParser.parse(content: config)
        t.expectEqual(entries.first?.proxyJump ?? [], ["bastion1", "bastion2"], "proxyJump list")
    }

    t.suite("SSHConfigParser.testWildcardHostIsNotConcrete") {
        let config = """
        Host *.example.com
            User deploy

        Host 10.0.*
            User admin
        """
        let entries = SSHConfigParser.parse(content: config)
        t.expectEqual(entries.count, 2, "two entries parsed")
        if entries.count == 2 {
            t.expect(!entries[0].isConcrete, "wildcard host is not concrete")
            t.expect(!entries[1].isConcrete, "wildcard host is not concrete")
        }
    }

    t.suite("SSHConfigParser.testParseDefaultPort") {
        let config = """
        Host myhost
            HostName example.com
        """
        let entries = SSHConfigParser.parse(content: config)
        t.expectEqual(entries.first?.port, 22, "default port is 22")
    }

    t.suite("SSHConfigParser.testParseLocalForward") {
        let config = """
        Host myhost
            HostName example.com
            LocalForward 8080 localhost:80
            LocalForward 3000 127.0.0.1:3000
        """
        let entries = SSHConfigParser.parse(content: config)
        t.expectEqual(entries.first?.localForwards.count, 2, "two local forwards")
        if let f = entries.first?.localForwards.first {
            t.expectEqual(f.localPort, 8080, "localPort")
            t.expectEqual(f.remoteHost, "localhost", "remoteHost")
            t.expectEqual(f.remotePort, 80, "remotePort")
        }
    }

    t.suite("SSHConfigParser.testSkipGlobalWildcard") {
        let config = """
        Host *
            ServerAliveInterval 60

        Host myhost
            HostName example.com
        """
        let entries = SSHConfigParser.parse(content: config)
        let concrete = entries.filter(\.isConcrete)
        t.expectEqual(concrete.count, 1, "one concrete entry")
        t.expectEqual(concrete.first?.hostAlias, "myhost", "concrete hostAlias")
    }

    t.suite("SSHConfigParser.testConvertToBookmark") {
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
        t.expectEqual(bookmark.name, "prod-web", "name")
        t.expectEqual(bookmark.host, "10.0.1.6", "host")
        t.expectEqual(bookmark.user, "deploy", "user")
        t.expectEqual(bookmark.jumpHosts, ["bastion"], "jumpHosts")
        t.expectEqual(bookmark.sshConfigHost, "prod-web", "sshConfigHost")
        if case .key(let file) = bookmark.auth {
            t.expectEqual(file, "~/.ssh/prod_key", "auth key file")
        } else {
            t.expect(false, "Expected .key auth")
        }
    }

    t.suite("SSHConfigParser.testEmptyConfig") {
        let entries = SSHConfigParser.parse(content: "")
        t.expect(entries.isEmpty, "empty config yields no entries")
    }

    t.suite("SSHConfigParser.testCommentsIgnored") {
        let config = """
        # This is a comment
        Host myhost
            # Another comment
            HostName example.com
        """
        let entries = SSHConfigParser.parse(content: config)
        t.expectEqual(entries.count, 1, "comments ignored, one entry")
    }
}
