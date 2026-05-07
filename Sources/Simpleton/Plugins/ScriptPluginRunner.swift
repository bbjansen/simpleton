// Sources/Simpleton/Plugins/ScriptPluginRunner.swift
import Foundation

/// Executes script plugins as child processes with JSON protocol.
final class ScriptPluginRunner {

    struct ScriptResult {
        let actions: [ScriptAction]
        let exitCode: Int32
        let timedOut: Bool
    }

    /// Run a script plugin with the given event context.
    /// Returns parsed actions from stdout, or empty if script produces no output.
    func run(plugin: ScriptPlugin, event: String, context: [String: Any], completion: @escaping (ScriptResult) -> Void) {
        // Check plugin is enabled and subscribes to this event
        guard plugin.isEnabled,
              plugin.subscribedEvents.contains(event) || event == "command" else {
            completion(ScriptResult(actions: [], exitCode: 0, timedOut: false))
            return
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        process.executableURL = plugin.entrypointURL
        process.currentDirectoryURL = plugin.directory
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        // Environment
        var env = ProcessInfo.processInfo.environment
        env["SIMPLETON_VERSION"] = "1.0.0"
        env["SIMPLETON_CONFIG_DIR"] = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Simpleton").path ?? ""
        process.environment = env

        // Start in a new process group for clean kill
        process.qualityOfService = .userInitiated

        do {
            try process.run()
        } catch {
            completion(ScriptResult(actions: [], exitCode: -1, timedOut: false))
            return
        }

        // Write context JSON to stdin
        var contextDict = context
        contextDict["event"] = event
        if let jsonData = try? JSONSerialization.data(withJSONObject: contextDict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            stdinPipe.fileHandleForWriting.write(Data((jsonString + "\n").utf8))
        }
        stdinPipe.fileHandleForWriting.closeFile()

        // Timeout: kill after 10 seconds
        var timedOut = false
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 10)
        timer.setEventHandler {
            timedOut = true
            // Kill entire process group
            let pid = process.processIdentifier
            if pid > 0 {
                kill(-pid, SIGTERM)
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    kill(-pid, SIGKILL)
                }
            }
            process.terminate()
        }
        timer.resume()

        // Read stdout asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()

            // Parse stdout as line-delimited JSON
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let actions = output
                .split(separator: "\n")
                .compactMap { line -> ScriptAction? in
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let actionType = json["action"] as? String else {
                        return nil
                    }
                    return ScriptAction(type: actionType, payload: json)
                }

            DispatchQueue.main.async {
                completion(ScriptResult(
                    actions: actions,
                    exitCode: process.terminationStatus,
                    timedOut: timedOut
                ))
            }
        }
    }
}

/// A parsed action from script stdout.
struct ScriptAction {
    let type: String       // "notify", "paste", "run-command", "set-env"
    let payload: [String: Any]
}
