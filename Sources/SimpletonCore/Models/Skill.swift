// Sources/SimpletonCore/Models/Skill.swift
import Foundation

public struct Skill: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var slug: String
    public var description: String
    public var icon: String
    public var parameters: [SkillParameter]
    public var systemPrompt: String
    public var builtIn: Bool
    public var version: Int

    public init(
        id: UUID = UUID(), name: String, slug: String, description: String,
        icon: String, parameters: [SkillParameter], systemPrompt: String,
        builtIn: Bool = false, version: Int = 1
    ) {
        self.id = id; self.name = name; self.slug = slug
        self.description = description; self.icon = icon
        self.parameters = parameters; self.systemPrompt = systemPrompt
        self.builtIn = builtIn; self.version = version
    }
}

public struct SkillParameter: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var label: String
    public var type: ParameterType
    public var placeholder: String?
    public var required: Bool
    public var autoFillHint: AutoFillHint?
    public var pickerOptions: [String]?

    public init(
        id: UUID = UUID(), name: String, label: String, type: ParameterType,
        placeholder: String? = nil, required: Bool = true,
        autoFillHint: AutoFillHint? = nil, pickerOptions: [String]? = nil
    ) {
        self.id = id; self.name = name; self.label = label; self.type = type
        self.placeholder = placeholder; self.required = required
        self.autoFillHint = autoFillHint; self.pickerOptions = pickerOptions
    }
}

public enum ParameterType: String, Codable {
    case text, number, filePath, picker
}

public enum AutoFillHint: String, Codable {
    case cwd, selection, sshHost, sshUser
}
