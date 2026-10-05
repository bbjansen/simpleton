// Sources/SimpletonCore/Core/CodeRefLinkParser.swift
import Foundation

/// A detected `path/to/File.ext:line` (or `File.ext:line:col`) reference inside a block of markdown.
///
/// `range` is the half-open character range of the whole token within the source string, so a renderer
/// can wrap exactly that span in a link. `path` is the file portion, `line`/`column` the 1-based
/// positions (`column` is nil when the token carries only a line).
public struct CodeRef: Equatable, Sendable {
    public let path: String
    public let line: Int
    public let column: Int?
    public let range: Range<String.Index>

    public init(path: String, line: Int, column: Int?, range: Range<String.Index>) {
        self.path = path
        self.line = line
        self.column = column
        self.range = range
    }
}

/// Detects code-reference tokens (`path/File.swift:42`, `File.swift:42:7`) in free text so the
/// spec-dev markdown preview can render them as clickable links back into the project.
///
/// Pure and deterministic (regex → ranges) so it can be exercised by CoreChecks without any UI.
public enum CodeRefLinkParser {

    /// The compiled detector. A path segment is non-whitespace that contains a dotted filename
    /// (`name.ext`) and ends at `:line` with an optional `:col`. Requiring a file extension before the
    /// colon keeps it from matching bare `word:123` prose or `http://` style tokens.
    ///
    /// - A leading boundary (`(?<=^|[\s(\[])`) prevents matching the tail of a URL like `a.b:1`
    ///   embedded in a longer run of non-space characters.
    /// - The path allows directories (`/`), dots, dashes, underscores, `~`, and `@`.
    /// - `line` and optional `column` are decimal.
    private static let pattern =
        #"(?<=^|[\s(\[`])([~./]?[\w./@\-]*[\w\-]\.[A-Za-z0-9]+):(\d+)(?::(\d+))?"#

    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }()

    /// All code references found in `text`, in source order. Empty when none match.
    public static func matches(in text: String) -> [CodeRef] {
        guard let regex, !text.isEmpty else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var results: [CodeRef] = []
        for m in regex.matches(in: text, options: [], range: full) {
            guard m.numberOfRanges >= 3,
                let whole = Range(m.range, in: text),
                let pathRange = Range(m.range(at: 1), in: text),
                let lineRange = Range(m.range(at: 2), in: text),
                let line = Int(text[lineRange])
            else { continue }
            let path = String(text[pathRange])
            var column: Int?
            if m.range(at: 3).location != NSNotFound, let colRange = Range(m.range(at: 3), in: text) {
                column = Int(text[colRange])
            }
            results.append(CodeRef(path: path, line: line, column: column, range: whole))
        }
        return results
    }

    /// Resolve a reference's path against a project root. Absolute and `~` paths are honored as-is;
    /// everything else is taken relative to `projectRoot`. Returns a standardized filesystem path.
    public static func resolvedPath(for ref: CodeRef, projectRoot: String) -> String {
        resolvedPath(path: ref.path, projectRoot: projectRoot)
    }

    /// Resolve a raw path string against a project root (shared by `resolvedPath(for:)` and callers
    /// that only have the string, e.g. a decoded URL host/path).
    public static func resolvedPath(path: String, projectRoot: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return (expanded as NSString).standardizingPath
        }
        let base = URL(fileURLWithPath: projectRoot, isDirectory: true)
        return base.appendingPathComponent(expanded).standardizedFileURL.path
    }

    /// The characters a code-reference path may contain: ASCII letters/digits plus `. / @ - _ ~` — the
    /// same class the detector matches. Deliberately excludes whitespace, quotes, control bytes, and
    /// shell/terminal metacharacters (`;`, `|`, `&`, `$`, backtick, `(`, `)`, `<`, `>`, `*`, `!`, …).
    private static let safePathScalars: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: "0123456789")
        set.insert(charactersIn: "._/@-~")
        return set
    }()

    /// Whether `path` is safe to compose into a shell/terminal command. References found by `matches`
    /// already satisfy this, but a path can arrive out-of-band — e.g. a crafted markdown link using the
    /// custom code-ref URL scheme directly, which bypasses the detector. Re-validating holds every path
    /// to the detector's safe shape: no control bytes (newlines, carriage returns, escape sequences) that
    /// a terminal emulator would interpret, and no whitespace or shell metacharacters. This is the guard
    /// against terminal command injection via a malicious code reference.
    public static func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf16.count <= 1024 else { return false }
        for scalar in path.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { return false }
            if !safePathScalars.contains(scalar) { return false }
        }
        return true
    }
}
