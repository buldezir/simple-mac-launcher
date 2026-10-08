import Foundation
import ServiceManagement

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case api
    case codex
    case claude
    case cursor
    case opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .api: return "API"
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .cursor: return "Cursor Agent"
        case .opencode: return "OpenCode"
        }
    }

    /// Binary name used for auto-detect and the settings hint.
    var commandName: String {
        switch self {
        case .api: return ""
        case .codex: return "codex"
        case .claude: return "claude"
        case .cursor: return "cursor-agent"
        case .opencode: return "opencode"
        }
    }

    var usesCLI: Bool { self != .api }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let providerKey = "ai.provider"
    private let endpointKey = "ai.endpoint"
    private let modelKey = "ai.model"
    private let apiKeyKey = "ai.apiKey"
    private let tavilyAPIKeyKey = "ai.tavilyAPIKey"
    private let codexModelKey = "ai.cliModel.codex"
    private let claudeModelKey = "ai.cliModel.claude"
    private let cursorModelKey = "ai.cliModel.cursor"
    private let opencodeModelKey = "ai.cliModel.opencode"
    private let codexPathKey = "ai.cliPath.codex"
    private let claudePathKey = "ai.cliPath.claude"
    private let cursorPathKey = "ai.cliPath.cursor"
    private let opencodePathKey = "ai.cliPath.opencode"
    private let cliAutoModeKey = "ai.cliAutoMode"
    private let aiHistoryLimitKey = "ai.historyLimit"
    private let showMenuBarIconKey = "launcher.showMenuBarIcon"
    private static let hotkeyKeyCodeKey = "launcher.hotkeyKeyCode"
    private static let hotkeyModifiersKey = "launcher.hotkeyModifiers"

    static let aiHistoryLimitDefault = 20
    static let aiHistoryLimitRange = 0...100

    private var isSyncingLaunchAtLogin = false

    @Published var aiProvider: AIProvider {
        didSet { UserDefaults.standard.set(aiProvider.rawValue, forKey: providerKey) }
    }

    @Published var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: endpointKey) }
    }

    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: modelKey) }
    }

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: apiKeyKey) }
    }

    /// Optional model override for the Codex CLI. Blank uses the CLI default.
    @Published var codexModel: String {
        didSet { UserDefaults.standard.set(codexModel, forKey: codexModelKey) }
    }

    /// Optional model override for the Claude CLI. Blank uses the CLI default.
    @Published var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: claudeModelKey) }
    }

    /// Optional model override for Cursor Agent. Blank uses the CLI default.
    @Published var cursorModel: String {
        didSet { UserDefaults.standard.set(cursorModel, forKey: cursorModelKey) }
    }

    /// Optional model override for the OpenCode CLI. Blank uses the CLI default.
    @Published var opencodeModel: String {
        didSet { UserDefaults.standard.set(opencodeModel, forKey: opencodeModelKey) }
    }

    /// Optional absolute path to the Codex executable. Blank auto-detects.
    @Published var codexCLIPath: String {
        didSet { UserDefaults.standard.set(codexCLIPath, forKey: codexPathKey) }
    }

    /// Optional absolute path to the Claude executable. Blank auto-detects.
    @Published var claudeCLIPath: String {
        didSet { UserDefaults.standard.set(claudeCLIPath, forKey: claudePathKey) }
    }

    /// Optional absolute path to the Cursor Agent executable. Blank auto-detects.
    @Published var cursorCLIPath: String {
        didSet { UserDefaults.standard.set(cursorCLIPath, forKey: cursorPathKey) }
    }

    /// Optional absolute path to the OpenCode executable. Blank auto-detects.
    @Published var opencodeCLIPath: String {
        didSet { UserDefaults.standard.set(opencodeCLIPath, forKey: opencodePathKey) }
    }

    /// When true, CLI providers may edit files and run commands. Off keeps read-only / ask mode.
    @Published var cliAutoMode: Bool {
        didSet { UserDefaults.standard.set(cliAutoMode, forKey: cliAutoModeKey) }
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

    /// Shortcut that shows or hides the launcher. Defaults to ⌥ Space.
    @Published var activationHotkey: ActivationHotkey {
        didSet { saveActivationHotkey(activationHotkey) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    @Published private(set) var launchAtLoginNeedsApproval = false

    var isAIConfigured: Bool {
        switch aiProvider {
        case .api:
            return !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .codex, .claude, .cursor, .opencode:
            return true
        }
    }

    func cliModel(for provider: AIProvider) -> String {
        switch provider {
        case .api: return ""
        case .codex: return codexModel
        case .claude: return claudeModel
        case .cursor: return cursorModel
        case .opencode: return opencodeModel
        }
    }

    func cliExecutableOverride(for provider: AIProvider) -> String {
        switch provider {
        case .api: return ""
        case .codex: return codexCLIPath
        case .claude: return claudeCLIPath
        case .cursor: return cursorCLIPath
        case .opencode: return opencodeCLIPath
        }
    }

    var isTavilyConfigured: Bool {
        !tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        aiProvider = AIProvider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .api
        endpoint = UserDefaults.standard.string(forKey: endpointKey) ?? "https://api.openai.com/v1"
        modelName = UserDefaults.standard.string(forKey: modelKey) ?? "gpt-4o-mini"
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        codexModel = UserDefaults.standard.string(forKey: codexModelKey) ?? ""
        claudeModel = UserDefaults.standard.string(forKey: claudeModelKey) ?? ""
        cursorModel = UserDefaults.standard.string(forKey: cursorModelKey) ?? ""
        opencodeModel = UserDefaults.standard.string(forKey: opencodeModelKey) ?? ""
        codexCLIPath = UserDefaults.standard.string(forKey: codexPathKey) ?? ""
        claudeCLIPath = UserDefaults.standard.string(forKey: claudePathKey) ?? ""
        cursorCLIPath = UserDefaults.standard.string(forKey: cursorPathKey) ?? ""
        opencodeCLIPath = UserDefaults.standard.string(forKey: opencodePathKey) ?? ""
        if UserDefaults.standard.object(forKey: cliAutoModeKey) == nil {
            cliAutoMode = false
        } else {
            cliAutoMode = UserDefaults.standard.bool(forKey: cliAutoModeKey)
        }
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
        activationHotkey = Self.loadActivationHotkey()
        launchAtLogin = false
        refreshLaunchAtLogin()
    }

    private static func loadActivationHotkey() -> ActivationHotkey {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: hotkeyKeyCodeKey) != nil,
              defaults.object(forKey: hotkeyModifiersKey) != nil else {
            return .default
        }
        let modifiers = UInt32(bitPattern: Int32(defaults.integer(forKey: hotkeyModifiersKey)))
        guard modifiers != 0 else { return .default }
        let keyCode = UInt32(bitPattern: Int32(defaults.integer(forKey: hotkeyKeyCodeKey)))
        return ActivationHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    private func saveActivationHotkey(_ hotkey: ActivationHotkey) {
        UserDefaults.standard.set(Int(hotkey.keyCode), forKey: Self.hotkeyKeyCodeKey)
        UserDefaults.standard.set(Int(hotkey.modifiers), forKey: Self.hotkeyModifiersKey)
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
