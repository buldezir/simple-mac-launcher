import Foundation

@MainActor
final class AskAIService: ObservableObject {
    @Published private(set) var answer: String = ""
    @Published private(set) var isStreaming = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAnswerMode = false

    private var task: Task<Void, Never>?
    private let settings: SettingsStore

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

        task = Task { [weak self] in
            do {
                try await self?.streamChat(url: url, apiKey: apiKey, model: model, prompt: trimmed)
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
    }

    private func streamChat(url: URL, apiKey: String, model: String, prompt: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "user", "content": prompt],
            ],
        ]
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

            var chunk = ""
            if let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                chunk = content
            } else if let message = first["message"] as? [String: Any],
                      let content = message["content"] as? String {
                chunk = content
            }

            if !chunk.isEmpty {
                await MainActor.run {
                    self.answer += chunk
                }
            }
        }

        await MainActor.run {
            self.isStreaming = false
        }
    }
}
