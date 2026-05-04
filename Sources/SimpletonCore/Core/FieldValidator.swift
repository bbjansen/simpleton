// Sources/SimpletonCore/Core/FieldValidator.swift
import Foundation

public enum FieldValidator {

    private static let hostnamePattern = #"^[a-zA-Z0-9._\-]+$"#
    private static let usernamePattern = #"^[a-zA-Z0-9._\-]+$"#

    public static func isValidHostname(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.range(of: hostnamePattern, options: .regularExpression) != nil
    }

    public static func isValidUsername(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.range(of: usernamePattern, options: .regularExpression) != nil
    }

    public static func isValidPort(_ port: Int) -> Bool {
        (1...65535).contains(port)
    }
}
