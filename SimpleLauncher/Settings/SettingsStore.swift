import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let endpointKey = "ai.endpoint"
    private let modelKey = "ai.model"
    private let apiKeyKey = "ai.apiKey"

    @Published var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: endpointKey) }
    }

    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: modelKey) }
    }

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: apiKeyKey) }
    }

    var isAIConfigured: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        endpoint = UserDefaults.standard.string(forKey: endpointKey) ?? "https://api.openai.com/v1"
        modelName = UserDefaults.standard.string(forKey: modelKey) ?? "gpt-4o-mini"
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    func chatCompletionsURL() -> URL? {
        var base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") {
            return URL(string: base)
        }
        return URL(string: base + "/chat/completions")
    }
}
