import Foundation

enum TavilySearchService {
    private static let maxExtractCharacters = 24_000

    struct Result: Sendable {
        let title: String
        let url: String
        let content: String
    }

    static func search(query: String, apiKey: String, maxResults: Int = 5) async throws -> [Result] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw NSError(domain: "Tavily", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Empty search query.",
            ])
        }

        let json = try await post(
            path: "search",
            apiKey: apiKey,
            body: [
                "query": trimmedQuery,
                "search_depth": "basic",
                "max_results": maxResults,
                "include_answer": false,
            ]
        )

        guard let results = json["results"] as? [[String: Any]] else {
            throw NSError(domain: "Tavily", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected Tavily search response.",
            ])
        }

        return results.compactMap { item in
            let title = item["title"] as? String ?? ""
            let url = item["url"] as? String ?? ""
            let content = item["content"] as? String ?? ""
            guard !url.isEmpty || !content.isEmpty else { return nil }
            return Result(title: title, url: url, content: content)
        }
    }

    static func extract(url pageURL: String, apiKey: String) async throws -> String {
        let trimmed = pageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw NSError(domain: "Tavily", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Invalid URL. Use an http(s) address.",
            ])
        }

        let json = try await post(
            path: "extract",
            apiKey: apiKey,
            body: [
                "urls": trimmed,
                "extract_depth": "basic",
                "format": "markdown",
            ]
        )

        if let failed = json["failed_results"] as? [[String: Any]],
           let first = failed.first {
            let error = first["error"] as? String ?? "Extraction failed."
            throw NSError(domain: "Tavily", code: 5, userInfo: [
                NSLocalizedDescriptionKey: error,
            ])
        }

        guard let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let raw = first["raw_content"] as? String,
              !raw.isEmpty
        else {
            throw NSError(domain: "Tavily", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "No content extracted from \(trimmed).",
            ])
        }

        let resultURL = first["url"] as? String ?? trimmed
        let content = truncate(raw, limit: maxExtractCharacters)
        return "Fetched content from \(resultURL):\n\n\(content)"
    }

    static func formatResults(_ results: [Result], query: String) -> String {
        if results.isEmpty {
            return "No web results found for \"\(query)\"."
        }
        var lines: [String] = ["Web search results for \"\(query)\":"]
        for (index, result) in results.enumerated() {
            lines.append("\(index + 1). \(result.title)")
            if !result.url.isEmpty {
                lines.append("   URL: \(result.url)")
            }
            if !result.content.isEmpty {
                lines.append("   \(result.content)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - HTTP

    private static func post(path: String, apiKey: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "https://api.tavily.com/\(path)") else {
            throw NSError(domain: "Tavily", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid Tavily URL.",
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "Tavily", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Tavily", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected Tavily response.",
            ])
        }
        return json
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]) + "\n\n[Truncated]"
    }
}
