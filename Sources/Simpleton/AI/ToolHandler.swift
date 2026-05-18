// Sources/Simpleton/AI/ToolHandler.swift
import Foundation
import SimpletonCore

struct ToolContext {
    let conversation: TabConversation?
    let focusedPane: PaneController
    let processRunner: ProcessRunner
    var memoryStore: MemoryStore?
    var skillStore: SkillStore?
}

protocol ToolHandler {
    static var handledTools: Set<String> { get }
    func handle(name: String, args: [String: Any], context: ToolContext) async -> String
}

struct ToolHandlerRegistry {
    private var handlers: [String: ToolHandler] = [:]

    init(_ handlerList: [ToolHandler]) {
        for handler in handlerList {
            for toolName in type(of: handler).handledTools {
                handlers[toolName] = handler
            }
        }
    }

    /// Register a handler for a set of dynamically-discovered tool names.
    /// Used by MCPToolBridge whose tools are not known at compile time.
    mutating func registerDynamic(handler: ToolHandler, toolNames: Set<String>) {
        for name in toolNames {
            handlers[name] = handler
        }
    }

    func handler(for toolName: String) -> ToolHandler? {
        handlers[toolName]
    }
}
