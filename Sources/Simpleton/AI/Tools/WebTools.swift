// Sources/Simpleton/AI/Tools/WebTools.swift
import Foundation

struct WebTools: ToolHandler {
    static let handledTools: Set<String> = ["web_search", "fetch_url"]

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        switch name {
        case "web_search":
            return await handleWebSearch(args)
        case "fetch_url":
            return await handleFetchURL(args)
        default:
            return "Unknown web tool: \(name)"
        }
    }

    // MARK: - web_search

    private func handleWebSearch(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "Missing 'query' parameter"
        }
        let count = min(args["count"] as? Int ?? 5, 10)

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return "Failed to encode search query"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                return "Search failed with HTTP \(status)"
            }
            guard let html = String(data: data, encoding: .utf8) else {
                return "Search failed: could not decode response"
            }
            let results = parseDuckDuckGoResults(html: html, maxResults: count)
            if results.isEmpty {
                return "No results found for: \(query)"
            }
            var output = "Search results for: \(query)\n\n"
            for (index, result) in results.enumerated() {
                output += "\(index + 1). \(result.title)\n"
                output += "   URL: \(result.url)\n"
                if !result.snippet.isEmpty {
                    output += "   \(result.snippet)\n"
                }
                output += "\n"
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Search failed: \(error.localizedDescription)"
        }
    }

    // MARK: - fetch_url

    private func handleFetchURL(_ args: [String: Any]) async -> String {
        guard let urlStr = args["url"] as? String,
              let url = URL(string: urlStr) else {
            return "Missing or invalid 'url' parameter"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? 0
            guard let body = String(data: data, encoding: .utf8) else {
                return "HTTP \(status) — could not decode response body"
            }
            let stripped = stripHTMLTags(body)
            let cleaned = collapseWhitespace(stripped)
            let maxChars = 5000
            let truncated = cleaned.count > maxChars
                ? String(cleaned.prefix(maxChars)) + "\n[... truncated, total \(cleaned.count) chars]"
                : cleaned
            return "HTTP \(status) — \(url.host ?? urlStr)\n\n\(truncated)"
        } catch {
            return "Fetch failed: \(error.localizedDescription)"
        }
    }

    // MARK: - HTML Parsing Helpers

    private struct SearchResult {
        let title: String
        let url: String
        let snippet: String
    }

    private func parseDuckDuckGoResults(html: String, maxResults: Int) -> [SearchResult] {
        var results: [SearchResult] = []
        let resultBlocks = html.components(separatedBy: "class=\"result__body")
        for block in resultBlocks.dropFirst() {
            if results.count >= maxResults { break }
            let title = extractTagContent(from: block, className: "result__a")
            let href = extractHref(from: block, className: "result__a")
            let snippet = extractTagContent(from: block, className: "result__snippet")
            if !title.isEmpty || !href.isEmpty {
                let cleanTitle = stripHTMLTags(title).trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanSnippet = stripHTMLTags(snippet).trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanURL = cleanDuckDuckGoURL(href)
                results.append(SearchResult(title: cleanTitle, url: cleanURL, snippet: cleanSnippet))
            }
        }
        return results
    }

    private func extractTagContent(from html: String, className: String) -> String {
        guard let classRange = html.range(of: "class=\"\(className)\"") else { return "" }
        let afterClass = String(html[classRange.upperBound...])
        guard let openEnd = afterClass.firstIndex(of: ">") else { return "" }
        let contentStart = afterClass.index(after: openEnd)
        let afterOpen = String(afterClass[contentStart...])
        if let closeRange = afterOpen.range(of: "</") {
            return String(afterOpen[..<closeRange.lowerBound])
        }
        return String(afterOpen.prefix(200))
    }

    private func extractHref(from html: String, className: String) -> String {
        guard let classRange = html.range(of: "class=\"\(className)\"") else { return "" }
        let beforeClass = String(html[..<classRange.lowerBound])
        guard let hrefRange = beforeClass.range(of: "href=\"", options: .backwards) else { return "" }
        let afterHref = String(beforeClass[hrefRange.upperBound...])
        if let quoteEnd = afterHref.firstIndex(of: "\"") {
            return String(afterHref[..<quoteEnd])
        }
        return ""
    }

    private func cleanDuckDuckGoURL(_ rawURL: String) -> String {
        if rawURL.contains("uddg="),
           let uddgRange = rawURL.range(of: "uddg=") {
            let afterUddg = String(rawURL[uddgRange.upperBound...])
            let encoded = afterUddg.components(separatedBy: "&").first ?? afterUddg
            return encoded.removingPercentEncoding ?? encoded
        }
        if rawURL.hasPrefix("//") {
            return "https:" + rawURL
        }
        return rawURL
    }

    private func stripHTMLTags(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return html
        }
        let range = NSRange(html.startIndex..., in: html)
        var result = regex.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        return result
    }

    private func collapseWhitespace(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }
}
