import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let endpointKey = "ai.endpoint"
    private let modelKey = "ai.model"
    private let apiKeyKey = "ai.apiKey"

    private var isSyncingLaunchAtLogin = false

    @Published var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: endpointKey) }
    }

    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: modelKey) }
    }

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: apiKeyKey) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    @Published private(set) var launchAtLoginNeedsApproval = false

    var isAIConfigured: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        endpoint = UserDefaults.standard.string(forKey: endpointKey) ?? "https://api.openai.com/v1"
        modelName = UserDefaults.standard.string(forKey: modelKey) ?? "gpt-4o-mini"
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        launchAtLogin = false
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        isSyncingLaunchAtLogin = true
        launchAtLogin = status == .enabled
        isSyncingLaunchAtLogin = false
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert UI if registration/unregistration fails.
        }
        refreshLaunchAtLogin()
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
