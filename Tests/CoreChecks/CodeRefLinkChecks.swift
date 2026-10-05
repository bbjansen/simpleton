import Foundation
import SimpletonCore

func runCodeRefLinkChecks(_ t: TestRunner) {
    t.suite("CodeRefLinkParser: basic path:line + path:line:col") {
        let text = "See Sources/App/Main.swift:42 and lib/util.rb:10:7 for details."
        let refs = CodeRefLinkParser.matches(in: text)
        t.expectEqual(refs.count, 2, "two references detected")
        t.expectEqual(refs.first?.path, "Sources/App/Main.swift", "first path")
        t.expectEqual(refs.first?.line, 42, "first line")
        t.expect(refs.first?.column == nil, "first has no column")
        t.expectEqual(refs.last?.path, "lib/util.rb", "second path")
        t.expectEqual(refs.last?.line, 10, "second line")
        t.expectEqual(refs.last?.column, 7, "second column")
    }

    t.suite("CodeRefLinkParser: range maps to the whole token") {
        let text = "edit foo/Bar.swift:5 now"
        guard let ref = CodeRefLinkParser.matches(in: text).first else {
            t.expect(false, "expected a reference")
            return
        }
        t.expectEqual(String(text[ref.range]), "foo/Bar.swift:5", "range covers the token exactly")
    }

    t.suite("CodeRefLinkParser: bare filename and leading dot paths") {
        let a = CodeRefLinkParser.matches(in: "File.swift:1")
        t.expectEqual(a.first?.path, "File.swift", "bare filename")
        t.expectEqual(a.first?.line, 1, "bare filename line")
        let b = CodeRefLinkParser.matches(in: "(./scripts/run.sh:88)")
        t.expectEqual(b.first?.path, "./scripts/run.sh", "relative dot-slash path")
        t.expectEqual(b.first?.line, 88, "dot-slash line")
    }

    t.suite("CodeRefLinkParser: ignores non-code colons and prose") {
        t.expectEqual(CodeRefLinkParser.matches(in: "Note: this is important").count, 0, "word:prose ignored")
        t.expectEqual(CodeRefLinkParser.matches(in: "ratio was 3:2 overall").count, 0, "number ratio ignored")
        t.expectEqual(
            CodeRefLinkParser.matches(in: "visit http://example.com:8080/x").count, 0, "url port ignored")
        t.expectEqual(CodeRefLinkParser.matches(in: "no extension here path/dir:10").count, 0, "no dotted file")
    }

    t.suite("CodeRefLinkParser: multiline (anchorsMatchLines)") {
        let text = "a.swift:1\nb.swift:2\nc.swift:3"
        t.expectEqual(CodeRefLinkParser.matches(in: text).count, 3, "one per line")
    }

    t.suite("CodeRefLinkParser.resolvedPath") {
        let root = "/tmp/proj"
        let rel = CodeRefLinkParser.resolvedPath(path: "src/Main.swift", projectRoot: root)
        t.expectEqual(rel, "/tmp/proj/src/Main.swift", "relative resolves under root")
        let abs = CodeRefLinkParser.resolvedPath(path: "/etc/hosts", projectRoot: root)
        t.expectEqual(abs, "/etc/hosts", "absolute path kept as-is")
        let dotdot = CodeRefLinkParser.resolvedPath(path: "a/../b.swift", projectRoot: root)
        t.expectEqual(dotdot, "/tmp/proj/b.swift", "dot-dot standardized away")
    }
}
