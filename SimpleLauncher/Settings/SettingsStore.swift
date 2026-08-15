import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let endpointKey = "ai.endpoint"
    private let modelKey = "ai.model"
    private let apiKeyKey = "ai.apiKey"
    private let tavilyAPIKeyKey = "ai.tavilyAPIKey"
    private let aiHistoryLimitKey = "ai.historyLimit"
    private let showMenuBarIconKey = "launcher.showMenuBarIcon"

    static let aiHistoryLimitDefault = 20
    static let aiHistoryLimitRange = 0...100

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

    /// Optional Tavily key. When set, Ask AI can call `web_search`.
    @Published var tavilyAPIKey: String {
        didSet { UserDefaults.standard.set(tavilyAPIKey, forKey: tavilyAPIKeyKey) }
    }

    /// How many completed AI prompts to retain for `/h` history. `0` disables storage.
    @Published var aiHistoryLimit: Int {
        didSet {
            let clamped = Self.clampedHistoryLimit(aiHistoryLimit)
            if clamped != aiHistoryLimit {
                aiHistoryLimit = clamped
                return
            }
            UserDefaults.standard.set(aiHistoryLimit, forKey: aiHistoryLimitKey)
        }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: showMenuBarIconKey) }
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

    var isTavilyConfigured: Bool {
        !tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        endpoint = UserDefaults.standard.string(forKey: endpointKey) ?? "https://api.openai.com/v1"
        modelName = UserDefaults.standard.string(forKey: modelKey) ?? "gpt-4o-mini"
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        tavilyAPIKey = UserDefaults.standard.string(forKey: tavilyAPIKeyKey) ?? ""
        if UserDefaults.standard.object(forKey: aiHistoryLimitKey) == nil {
            aiHistoryLimit = Self.aiHistoryLimitDefault
        } else {
            aiHistoryLimit = Self.clampedHistoryLimit(
                UserDefaults.standard.integer(forKey: aiHistoryLimitKey)
            )
        }
        if UserDefaults.standard.object(forKey: showMenuBarIconKey) == nil {
            showMenuBarIcon = true
        } else {
            showMenuBarIcon = UserDefaults.standard.bool(forKey: showMenuBarIconKey)
        }
        launchAtLogin = false
        refreshLaunchAtLogin()
    }

    static func clampedHistoryLimit(_ value: Int) -> Int {
        min(max(value, aiHistoryLimitRange.lowerBound), aiHistoryLimitRange.upperBound)
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
