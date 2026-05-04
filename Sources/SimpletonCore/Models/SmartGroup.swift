// Sources/SimpletonCore/Models/SmartGroup.swift
import Foundation

public enum RuleField: String, Codable {
    case hostname, ip, ipRange = "ip-range", user, port, tag
    case jumpHost = "jump-host", identityFile = "identity-file", name, notes
}

public enum RuleOperator: String, Codable {
    case equals, contains, startsWith = "starts-with", endsWith = "ends-with"
    case matches, cidr
}

public enum RuleCombinator: String, Codable {
    case and = "AND"
    case or = "OR"
}

public struct SmartGroupRule: Codable, Equatable {
    public let field: RuleField
    public let `operator`: RuleOperator
    public let value: String

    public init(field: RuleField, operator: RuleOperator, value: String) {
        self.field = field
        self.operator = `operator`
        self.value = value
    }

    public func matches(_ bookmark: Bookmark) -> Bool {
        let fieldValue: String? = {
            switch field {
            case .hostname, .ip: return bookmark.host
            case .name: return bookmark.name
            case .user: return bookmark.user
            case .port: return String(bookmark.port)
            case .notes: return bookmark.notes
            case .tag:
                return bookmark.tags.contains(where: { evaluate($0) }) ? value : nil
            case .jumpHost:
                return bookmark.jumpHosts.first
            case .identityFile:
                if case .key(let file) = bookmark.auth { return file }
                return nil
            case .ipRange: return bookmark.host
            }
        }()

        if field == .tag {
            return fieldValue != nil
        }

        guard let fieldValue else { return false }
        return evaluate(fieldValue)
    }

    private func evaluate(_ input: String) -> Bool {
        switch `operator` {
        case .equals: return input == value
        case .contains: return input.localizedCaseInsensitiveContains(value)
        case .startsWith: return input.lowercased().hasPrefix(value.lowercased())
        case .endsWith: return input.lowercased().hasSuffix(value.lowercased())
        case .matches:
            return (try? NSRegularExpression(pattern: value))
                .map { $0.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil } ?? false
        case .cidr: return false // CIDR matching implemented in a later task
        }
    }
}

public struct SmartGroup: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var color: String
    public var combinator: RuleCombinator
    public var rules: [SmartGroupRule]

    public init(id: UUID = UUID(), name: String, color: String, combinator: RuleCombinator, rules: [SmartGroupRule]) {
        self.id = id
        self.name = name
        self.color = color
        self.combinator = combinator
        self.rules = rules
    }

    public func matches(_ bookmark: Bookmark) -> Bool {
        guard !rules.isEmpty else { return false }
        switch combinator {
        case .or: return rules.contains { $0.matches(bookmark) }
        case .and: return rules.allSatisfy { $0.matches(bookmark) }
        }
    }
}

public struct SmartGroupFile: Codable {
    public let version: Int
    public var groups: [SmartGroup]

    public init(version: Int = 1, groups: [SmartGroup] = []) {
        self.version = version
        self.groups = groups
    }
}
