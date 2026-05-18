// Sources/Simpleton/AI/ProjectIndexer.swift
import Foundation

struct ProjectIndex {
    let gitRoot: String
    let projectName: String
    let techStack: [String]
    let fileCount: Int
    let topLevelDirs: [String]
    let configFiles: [String]

    var promptSummary: String {
        var parts: [String] = []
        parts.append("Project: \(projectName)")
        if !techStack.isEmpty {
            parts.append("Stack: \(techStack.joined(separator: ", "))")
        }
        parts.append("Files: \(fileCount)")
        if !topLevelDirs.isEmpty {
            parts.append("Dirs: \(topLevelDirs.joined(separator: ", "))")
        }
        let summary = parts.joined(separator: " | ")
        if summary.count > 500 {
            return String(summary.prefix(497)) + "..."
        }
        return summary
    }
}

final class ProjectIndexer {
    private let processRunner = ProcessRunner()

    private var cache: (gitRoot: String, index: ProjectIndex)?

    private let configFileNames: [String] = [
        "package.json",
        "Cargo.toml",
        "Package.swift",
        "pyproject.toml",
        "go.mod",
        "Makefile",
        "docker-compose.yml",
        "docker-compose.yaml",
        ".env.example",
    ]

    private let stackSignals: [(file: String, stack: String)] = [
        ("package.json", "Node.js"),
        ("tsconfig.json", "TypeScript"),
        ("Cargo.toml", "Rust"),
        ("Package.swift", "Swift"),
        ("pyproject.toml", "Python"),
        ("go.mod", "Go"),
        ("Gemfile", "Ruby"),
        ("pom.xml", "Java"),
        ("build.gradle", "Kotlin/Java"),
        ("docker-compose.yml", "Docker"),
        ("docker-compose.yaml", "Docker"),
        ("Dockerfile", "Docker"),
        ("Makefile", "Make"),
        (".env.example", "Env config"),
    ]

    func index(for directory: String) async -> ProjectIndex? {
        let gitRoot = await detectGitRoot(directory)
        guard let gitRoot else { return nil }

        if let cached = cache, cached.gitRoot == gitRoot {
            return cached.index
        }

        let files = await listTrackedFiles(gitRoot)
        guard !files.isEmpty else { return nil }

        let fileSet = Set(files)
        let projectName = URL(fileURLWithPath: gitRoot).lastPathComponent
        let techStack = detectTechStack(files: fileSet)
        let topLevelDirs = extractTopLevelDirs(files: files)
        let configFiles = configFileNames.filter { fileSet.contains($0) }

        let result = ProjectIndex(
            gitRoot: gitRoot,
            projectName: projectName,
            techStack: techStack,
            fileCount: files.count,
            topLevelDirs: topLevelDirs,
            configFiles: configFiles
        )

        cache = (gitRoot: gitRoot, index: result)
        return result
    }

    // MARK: - Git helpers

    private func detectGitRoot(_ directory: String) async -> String? {
        let output = await processRunner.run(
            "/usr/bin/git",
            args: ["rev-parse", "--show-toplevel"],
            cwd: directory
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("Error:") || trimmed.contains("fatal:") {
            return nil
        }
        return trimmed
    }

    private func listTrackedFiles(_ gitRoot: String) async -> [String] {
        let output = await processRunner.run(
            "/usr/bin/git",
            args: ["ls-files"],
            cwd: gitRoot
        )
        if output.isEmpty || output.hasPrefix("Error:") {
            return []
        }
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - Analysis

    private func detectTechStack(files: Set<String>) -> [String] {
        var seen = Set<String>()
        var stack: [String] = []
        for signal in stackSignals {
            if files.contains(signal.file), !seen.contains(signal.stack) {
                seen.insert(signal.stack)
                stack.append(signal.stack)
            }
        }
        return stack
    }

    private func extractTopLevelDirs(files: [String]) -> [String] {
        var dirs = Set<String>()
        for file in files {
            if let slash = file.firstIndex(of: "/") {
                dirs.insert(String(file[file.startIndex..<slash]))
            }
        }
        return dirs.sorted()
    }
}
