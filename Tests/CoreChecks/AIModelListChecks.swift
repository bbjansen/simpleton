// Tests/CoreChecks/AIModelListChecks.swift
import Foundation
import SimpletonCore

func runAIModelListChecks(_ t: TestRunner) {
    t.suite("AIModelList.openAIShape") {
        let json = """
        {"object":"list","data":[{"id":"gpt-4o"},{"id":"gpt-4o-mini"},{"id":"o3"}]}
        """.data(using: .utf8)!
        let models = AIModelListParser.parse(json, format: .openAI)
        t.expectEqual(models, ["gpt-4o", "gpt-4o-mini", "o3"], "openAI ids in order")
    }

    t.suite("AIModelList.anthropicShape") {
        let json = """
        {"data":[{"id":"claude-sonnet-4-20250514","type":"model"},{"id":"claude-opus-4-20250514"}]}
        """.data(using: .utf8)!
        let models = AIModelListParser.parse(json, format: .anthropic)
        t.expectEqual(models, ["claude-sonnet-4-20250514", "claude-opus-4-20250514"], "anthropic ids")
    }

    t.suite("AIModelList.ollamaTagsShape") {
        let json = """
        {"models":[{"name":"llama3:latest","size":1},{"name":"codellama:7b"}]}
        """.data(using: .utf8)!
        let models = AIModelListParser.parse(json, format: .ollamaTags)
        t.expectEqual(models, ["llama3:latest", "codellama:7b"], "ollama names")
    }

    t.suite("AIModelList.dedupPreservesOrder") {
        let json = """
        {"data":[{"id":"a"},{"id":"b"},{"id":"a"},{"id":"c"},{"id":"b"}]}
        """.data(using: .utf8)!
        t.expectEqual(AIModelListParser.parse(json, format: .openAI), ["a", "b", "c"], "dedup keeps first order")
    }

    t.suite("AIModelList.malformedIsEmpty") {
        t.expectEqual(AIModelListParser.parse(Data("not json".utf8), format: .openAI), [], "garbage → empty")
        t.expectEqual(AIModelListParser.parse(Data("{}".utf8), format: .openAI), [], "missing data → empty")
        t.expectEqual(AIModelListParser.parse(Data("{\"data\":[{\"noid\":1}]}".utf8), format: .openAI), [], "no id fields → empty")
    }
}
