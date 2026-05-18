// Sources/Simpleton/AI/Tools/FileTools.swift
import Foundation

struct FileTools: ToolHandler {
    static let handledTools: Set<String> = [
        "read_file", "write_file", "edit_file", "list_directory", "search_files",
    ]

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        switch name {
        case "read_file":
            return handleReadFile(args)
        case "write_file":
            return handleWriteFile(args)
        case "edit_file":
            return handleEditFile(args)
        case "list_directory":
            return handleListDirectory(args, processRunner: context.processRunner)
        case "search_files":
            return handleSearchFiles(args)
        default:
            return "Unknown file tool: \(name)"
        }
    }

    private func handleReadFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else {
            return "Missing 'path' parameter"
        }
        let expandedPath = NSString(string: path).expandingTildeInPath
        do {
            let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
            let maxChars = 10_000
            let truncated = content.count > maxChars
            return truncated
                ? String(content.prefix(maxChars)) + "\n\n[... truncated at \(maxChars) chars, file is \(content.count) chars total]"
                : content
        } catch {
            return "Error reading \(path): \(error.localizedDescription)"
        }
    }

    private func handleWriteFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String,
              let content = args["content"] as? String else {
            return "Missing 'path' or 'content' parameter"
        }
        let expandedPath = NSString(string: path).expandingTildeInPath
        do {
            let dir = (expandedPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
            return "Wrote \(content.count) chars to \(path)"
        } catch {
            return "Error writing \(path): \(error.localizedDescription)"
        }
    }

    private func handleEditFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String,
              let oldText = args["old_text"] as? String,
              let newText = args["new_text"] as? String else {
            return "Missing 'path', 'old_text', or 'new_text' parameter"
        }
        let trimWhitespace = args["trim_whitespace"] as? Bool ?? false
        let expandedPath = NSString(string: path).expandingTildeInPath
        do {
            var content = try String(contentsOfFile: expandedPath, encoding: .utf8)
            let searchText: String
            var searchContent: String = content
            if trimWhitespace {
                // Normalize both content and search text by collapsing runs of whitespace
                let normalize = { (s: String) -> String in
                    s.components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }
                searchText = normalize(oldText)
                searchContent = normalize(content)
            } else {
                searchText = oldText
            }
            let occurrences = searchContent.components(separatedBy: searchText).count - 1
            if occurrences == 0 {
                return "Error: old_text not found in \(path). Make sure it matches exactly (including whitespace). Tip: set trim_whitespace=true to ignore whitespace differences."
            } else if occurrences > 1 && !(args["replace_all"] as? Bool ?? false) {
                return "Error: old_text found \(occurrences) times in \(path). Set replace_all=true or provide more context to make the match unique."
            } else {
                if trimWhitespace {
                    // Split old_text on whitespace, rejoin with \s+ pattern for flexible matching
                    let words = oldText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    let pattern = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "\\s+")
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                       let range = Range(match.range, in: content) {
                        content.replaceSubrange(range, with: newText)
                    }
                } else if args["replace_all"] as? Bool ?? false {
                    content = content.replacingOccurrences(of: oldText, with: newText)
                } else {
                    if let range = content.range(of: oldText) {
                        content.replaceSubrange(range, with: newText)
                    }
                }
                try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
                return "Edited \(path): replaced \(oldText.count) chars with \(newText.count) chars"
            }
        } catch {
            return "Error editing \(path): \(error.localizedDescription)"
        }
    }

    private func handleListDirectory(_ args: [String: Any], processRunner: ProcessRunner) -> String {
        let path = args["path"] as? String ?? "."
        let expandedPath = NSString(string: path).expandingTildeInPath
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: expandedPath)
            var lines: [String] = []
            for item in items.sorted() {
                let fullPath = (expandedPath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
                let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath)
                let size = attrs?[.size] as? UInt64 ?? 0
                let suffix = isDir.boolValue ? "/" : ""
                lines.append("\(item)\(suffix)  \(isDir.boolValue ? "dir" : processRunner.formatFileSize(size))")
            }
            return lines.isEmpty ? "[Empty directory]" : lines.joined(separator: "\n")
        } catch {
            return "Error listing \(path): \(error.localizedDescription)"
        }
    }

    private func handleSearchFiles(_ args: [String: Any]) -> String {
        guard let pattern = args["pattern"] as? String else {
            return "Missing 'pattern' parameter"
        }
        let dir = args["directory"] as? String ?? "."
        let expandedDir = NSString(string: dir).expandingTildeInPath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-r", "-n", "-l", "--include=*", pattern, expandedDir]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            if lines.isEmpty {
                return "No files matching '\(pattern)' in \(dir)"
            } else {
                let maxFiles = 50
                let truncated = lines.count > maxFiles
                return lines.prefix(maxFiles).joined(separator: "\n") + (truncated ? "\n\n[... and \(lines.count - maxFiles) more files]" : "")
            }
        } catch {
            return "Error searching: \(error.localizedDescription)"
        }
    }
}
