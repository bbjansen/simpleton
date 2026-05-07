// Sources/Simpleton/Plugins/ScriptActionHandler.swift
import AppKit
import UserNotifications

/// Processes actions emitted by script plugins, with permission checking.
final class ScriptActionHandler {

    /// Handle a script action. Returns true if the action was processed.
    func handle(action: ScriptAction, plugin: ScriptPlugin, pasteHandler: ((String) -> Void)?, commandHandler: ((String) -> Void)?) -> Bool {
        // Permission check
        guard plugin.grantedPermissions.contains(action.type) else {
            return false
        }

        switch action.type {
        case "notify":
            handleNotify(action: action, plugin: plugin)
            return true
        case "paste":
            if let text = action.payload["text"] as? String {
                pasteHandler?(text)
            }
            return true
        case "run-command":
            if let commandId = action.payload["commandId"] as? String {
                commandHandler?(commandId)
            }
            return true
        case "set-env":
            if let key = action.payload["key"] as? String,
               let value = action.payload["value"] as? String {
                setenv(key, value, 1)
            }
            return true
        default:
            return false
        }
    }

    private func handleNotify(action: ScriptAction, plugin: ScriptPlugin) {
        let title = action.payload["title"] as? String ?? plugin.name
        let message = action.payload["message"] as? String ?? ""

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "simpleton.plugin.\(plugin.name).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
