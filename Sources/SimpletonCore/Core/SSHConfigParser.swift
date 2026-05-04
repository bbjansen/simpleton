// Sources/SimpletonCore/Core/SSHConfigParser.swift
import Foundation

public struct SSHForward: Equatable {
    public let localPort: Int
    public let remoteHost: String
    public let remotePort: Int

    public init(localPort: Int, remoteHost: String, remotePort: Int) {
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }
}

public struct SSHConfigEntry: Equatable {
    public let hostAlias: String
    public var hostname: String?
    public var user: String?
    public var port: Int
    public var identityFile: String?
    public var proxyJump: [String]
    public var localForwards: [SSHForward]
    public let isConcrete: Bool

    public init(
        hostAlias: String,
        hostname: String? = nil,
        user: String? = nil,
        port: Int = 22,
        identityFile: String? = nil,
        proxyJump: [String] = [],
        localForwards: [SSHForward] = [],
        isConcrete: Bool = true
    ) {
        self.hostAlias = hostAlias
        self.hostname = hostname
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.proxyJump = proxyJump
        self.localForwards = localForwards
        self.isConcrete = isConcrete
    }

    public func toBookmark() -> Bookmark {
        let auth: AuthMethod
        if let file = identityFile {
            auth = .key(identityFile: file)
        } else {
            auth = .agent
        }

        return Bookmark(
            name: hostAlias,
            host: hostname ?? hostAlias,
            port: port,
            user: user,
            auth: auth,
            jumpHosts: proxyJump,
            portForwards: localForwards.map {
                PortForward(direction: .local, localPort: $0.localPort, remoteHost: $0.remoteHost, remotePort: $0.remotePort)
            },
            sshConfigHost: hostAlias
        )
    }
}

public enum SSHConfigParser {

    public static func parse(content: String) -> [SSHConfigEntry] {
        var entries: [SSHConfigEntry] = []
        var current: SSHConfigEntry?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count >= 2 else { continue }

            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if key == "host" {
                if let entry = current { entries.append(entry) }
                let isConcrete = !value.contains("*") && !value.contains("?")
                current = SSHConfigEntry(hostAlias: value, isConcrete: isConcrete)
            } else if var entry = current {
                switch key {
                case "hostname": entry.hostname = value
                case "user": entry.user = value
                case "port": entry.port = Int(value) ?? 22
                case "identityfile": entry.identityFile = value
                case "proxyjump":
                    entry.proxyJump = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                case "localforward":
                    if let forward = parseForward(value) {
                        entry.localForwards.append(forward)
                    }
                default: break
                }
                current = entry
            }
        }

        if let entry = current { entries.append(entry) }
        return entries
    }

    public static func parseFile(at path: String) -> [SSHConfigEntry] {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expandedPath) else { return [] }

        var entries = parse(content: content)

        // Handle Include directives
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            if parts.count == 2 && parts[0].lowercased() == "include" {
                let includePath = NSString(string: parts[1]).expandingTildeInPath
                let included = parseFile(at: includePath)
                entries.append(contentsOf: included)
            }
        }

        return entries
    }

    private static func parseForward(_ value: String) -> SSHForward? {
        // Format: localPort remoteHost:remotePort
        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let localPort = Int(parts[0]) else { return nil }

        let remote = parts[1].split(separator: ":", maxSplits: 1).map(String.init)
        guard remote.count == 2,
              let remotePort = Int(remote[1]) else { return nil }

        return SSHForward(localPort: localPort, remoteHost: remote[0], remotePort: remotePort)
    }
}
