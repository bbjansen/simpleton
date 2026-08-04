// Sources/Simpleton/SSHManager.swift
import Foundation
import SimpletonCore

enum SSHManager {

    struct SSHCommand {
        let executable: String
        let arguments: [String]
        let environment: [String]
    }

    /// Build an ssh command from a bookmark. Returns nil if bookmark fields are invalid.
    static func buildCommand(from bookmark: Bookmark, config: AppConfig) -> SSHCommand? {
        // Validate required fields
        guard FieldValidator.isValidHostname(bookmark.host) else { return nil }
        guard FieldValidator.isValidPort(bookmark.port) else { return nil }
        if let user = bookmark.user {
            guard FieldValidator.isValidUsername(user) else { return nil }
        }

        var args: [String] = []

        // Port (if non-default)
        if bookmark.port != 22 {
            args.append(contentsOf: ["-p", String(bookmark.port)])
        }

        // Identity file
        if case .key(let identityFile) = bookmark.auth {
            let expanded = NSString(string: identityFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expanded])
        }

        // Jump hosts (ProxyJump)
        if !bookmark.jumpHosts.isEmpty {
            let jumpChain = bookmark.jumpHosts.joined(separator: ",")
            args.append(contentsOf: ["-J", jumpChain])
        }

        // Port forwards
        for pf in bookmark.portForwards {
            guard FieldValidator.isValidPort(pf.localPort),
                FieldValidator.isValidPort(pf.remotePort),
                FieldValidator.isValidHostname(pf.remoteHost)
            else { continue }

            let spec = "\(pf.localPort):\(pf.remoteHost):\(pf.remotePort)"
            switch pf.direction {
            case .local:
                args.append(contentsOf: ["-L", spec])
            case .remote:
                args.append(contentsOf: ["-R", spec])
            }
        }

        // Keepalive
        if config.ssh.keepaliveInterval > 0 {
            args.append(contentsOf: ["-o", "ServerAliveInterval=\(config.ssh.keepaliveInterval)"])
            args.append(contentsOf: ["-o", "ServerAliveCountMax=3"])
        }

        // Agent forwarding
        if config.ssh.agentForwarding {
            args.append("-A")
        }

        // X11 forwarding
        if config.ssh.x11Forwarding {
            args.append("-X")
        }

        // ControlMaster multiplexing
        if config.ssh.controlMaster {
            args.append(contentsOf: ["-o", "ControlMaster=auto"])
            args.append(contentsOf: ["-o", "ControlPath=~/.ssh/simpleton-%r@%h:%p"])
            args.append(contentsOf: ["-o", "ControlPersist=600"])
        }

        // Destination (user@host)
        let user = bookmark.user ?? config.ssh.defaultUser
        if let user = user {
            args.append("\(user)@\(bookmark.host)")
        } else {
            args.append(bookmark.host)
        }

        // Build environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = config.general.termVariable
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        let envArray = env.map { "\($0.key)=\($0.value)" }

        return SSHCommand(
            executable: "/usr/bin/ssh",
            arguments: args,
            environment: envArray
        )
    }

    /// Build a display string for the connection (for pane title bar).
    static func connectionTitle(for bookmark: Bookmark) -> String {
        let user = bookmark.user.map { "\($0)@" } ?? ""
        let port = bookmark.port != 22 ? ":\(bookmark.port)" : ""
        return "\(user)\(bookmark.host)\(port)"
    }
}
