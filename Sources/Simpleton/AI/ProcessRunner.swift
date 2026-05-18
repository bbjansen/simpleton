// Sources/Simpleton/AI/ProcessRunner.swift
import Foundation

struct ProcessRunner {
    func run(_ executable: String, args: [String], cwd: String? = nil) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: NSString(string: cwd).expandingTildeInPath)
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            let maxChars = 8000
            if output.count > maxChars {
                return String(output.prefix(maxChars)) + "\n[... truncated]"
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func formatFileSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes / (1024 * 1024)) MB"
    }

    func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        if hours > 24 { return "\(hours / 24)d \(hours % 24)h" }
        return "\(hours)h \(mins)m"
    }
}
