import Foundation

@MainActor
final class AskAIService: ObservableObject {
    @Published private(set) var answer: String = ""
    @Published private(set) var isStreaming = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAnswerMode = false
    /// Shown in the answer pane while working (e.g. Thinking… / Searching…).
    @Published private(set) var statusText: String = "Thinking…"

    private var task: Task<Void, Never>?
    private let settings: SettingsStore
    private let maxToolRounds = 3

    init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    func ask(_ prompt: String) {
        cancel()
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isAnswerMode = true
        answer = ""
        errorMessage = nil
        statusText = "Thinking…"

        guard settings.isAIConfigured else {
            errorMessage = "Configure endpoint, API key, and model name in Settings."
            return
        }
        guard let url = settings.chatCompletionsURL() else {
            errorMessage = "Invalid endpoint URL."
            return
        }

        isStreaming = true
        let apiKey = settings.apiKey
        let model = settings.modelName
        let tavilyKey = settings.isTavilyConfigured ? settings.tavilyAPIKey : nil

        task = Task { [weak self] in
            do {
                try await self?.runConversation(
                    url: url,
                    apiKey: apiKey,
                    model: model,
                    prompt: trimmed,
                    tavilyAPIKey: tavilyKey
                )
            } catch is CancellationError {
                // ignored
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                    self?.isStreaming = false
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    func exitAnswerMode() {
        cancel()
        isAnswerMode = false
        answer = ""
        errorMessage = nil
        statusText = "Thinking…"
    }

    // MARK: - Agent loop

    private func runConversation(
        url: URL,
        apiKey: String,
        model: String,
        prompt: String,
        tavilyAPIKey: String?
    ) async throws {
        var messages: [[String: Any]] = []
        if tavilyAPIKey != nil {
            messages.append([
                "role": "system",
                "content": """
                You have web_search and web_fetch tools. Use web_search for current events, \
                facts you are unsure about, news, prices, versions, or "latest". Use web_fetch \
                to read a specific URL in full (e.g. after search finds a promising link). \
                Cite source URLs briefly. Answer concisely in markdown.
                """,
            ])
        }
        messages.append(["role": "user", "content": prompt])

        let tools: [[String: Any]]? = tavilyAPIKey.map { _ in
            [Self.webSearchTool, Self.webFetchTool]
        }

        for round in 0..<maxToolRounds {
            try Task.checkCancellation()
            await MainActor.run { self.statusText = "Thinking…" }

            let turn = try await streamTurn(
                url: url,
                apiKey: apiKey,
                model: model,
                messages: messages,
                tools: tools
            )

            if turn.toolCalls.isEmpty {
                await MainActor.run { self.isStreaming = false }
                return
            }

            // Model requested tools — keep any preamble out of the final answer pane.
            await MainActor.run { self.answer = "" }

            var assistantMessage: [String: Any] = [
                "role": "assistant",
                "tool_calls": turn.toolCalls.map(\.asAPIObject),
            ]
            if !turn.content.isEmpty {
                assistantMessage["content"] = turn.content
            }
            messages.append(assistantMessage)

            for call in turn.toolCalls {
                try Task.checkCancellation()
                let resultContent = try await executeToolCall(call, tavilyAPIKey: tavilyAPIKey)
                messages.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": resultContent,
                ])
            }
        }

        // Final pass without tools if we hit the round limit mid-search.
        await MainActor.run { self.statusText = "Thinking…" }
        _ = try await streamTurn(
            url: url,
            apiKey: apiKey,
            model: model,
            messages: messages,
            tools: nil
        )
        await MainActor.run { self.isStreaming = false }
    }

    private func executeToolCall(_ call: ToolCall, tavilyAPIKey: String?) async throws -> String {
        switch call.name {
        case "web_search":
            guard let tavilyAPIKey, !tavilyAPIKey.isEmpty else {
                return "Web search is not configured. Tell the user to add a Tavily API key in Settings."
            }
            let query = Self.parseStringArgument("query", from: call.arguments)
            await MainActor.run { self.statusText = "Searching…" }
            let results = try await TavilySearchService.search(query: query, apiKey: tavilyAPIKey)
            return TavilySearchService.formatResults(results, query: query)
        case "web_fetch":
            guard let tavilyAPIKey, !tavilyAPIKey.isEmpty else {
                return "Web fetch is not configured. Tell the user to add a Tavily API key in Settings."
            }
            let pageURL = Self.parseStringArgument("url", from: call.arguments)
            await MainActor.run { self.statusText = "Fetching…" }
            return try await TavilySearchService.extract(url: pageURL, apiKey: tavilyAPIKey)
        default:
            return "Unknown tool \"\(call.name)\"."
        }
    }

    // MARK: - Streaming turn

    private struct StreamTurn {
        var content: String = ""
        var toolCalls: [ToolCall] = []
    }

    private struct ToolCall {
        var id: String
        var name: String
        var arguments: String

        var asAPIObject: [String: Any] {
            [
                "id": id,
                "type": "function",
                "function": [
                    "name": name,
                    "arguments": arguments,
                ],
            ]
        }
    }

    private func streamTurn(
        url: URL,
        apiKey: String,
        model: String,
        messages: [[String: Any]],
        tools: [[String: Any]]?
    ) async throws -> StreamTurn {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages,
        ]
        if let tools {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 4096 { break }
            }
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "AskAI", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }

        var turn = StreamTurn()
        var pendingTools: [Int: (id: String, name: String, arguments: String)] = [:]

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first
            else { continue }

            let delta = first["delta"] as? [String: Any]
                ?? (first["message"] as? [String: Any])
                ?? [:]

            if let content = delta["content"] as? String, !content.isEmpty {
                turn.content += content
                // Only show streamed text when we're not accumulating tool calls.
                if pendingTools.isEmpty {
                    await MainActor.run {
                        self.answer += content
                    }
                }
            }

            if let toolDeltas = delta["tool_calls"] as? [[String: Any]] {
                for toolDelta in toolDeltas {
                    let index = toolDelta["index"] as? Int ?? 0
                    var entry = pendingTools[index] ?? (id: "", name: "", arguments: "")
                    if let id = toolDelta["id"] as? String, !id.isEmpty {
                        entry.id += id
                    }
                    if let function = toolDelta["function"] as? [String: Any] {
                        if let name = function["name"] as? String, !name.isEmpty {
                            entry.name += name
                        }
                        if let arguments = function["arguments"] as? String {
                            entry.arguments += arguments
                        }
                    }
                    pendingTools[index] = entry
                }
            }
        }

        turn.toolCalls = pendingTools
            .sorted { $0.key < $1.key }
            .compactMap { _, value in
                let id = value.id.isEmpty ? "call_\(UUID().uuidString)" : value.id
                let name = value.name
                guard !name.isEmpty else { return nil }
                return ToolCall(id: id, name: name, arguments: value.arguments)
            }

        return turn
    }

    // MARK: - Tool schema helpers

    private static let webSearchTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "web_search",
            "description": "Search the web for up-to-date information. Returns titles, URLs, and snippets.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The search query to look up.",
                    ],
                ],
                "required": ["query"],
            ],
        ],
    ]

    private static let webFetchTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "web_fetch",
            "description": "Fetch and read the full content of a specific web page URL as markdown.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": [
                        "type": "string",
                        "description": "The http(s) URL of the page to fetch.",
                    ],
                ],
                "required": ["url"],
            ],
        ],
    ]

    private static func parseStringArgument(_ key: String, from argumentsJSON: String) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = json[key] as? String, !value.isEmpty {
            return value
        }
        return argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
