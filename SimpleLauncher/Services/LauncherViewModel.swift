import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { handleQueryChange(from: oldValue) }
    }
    @Published private(set) var results: [SearchResult] = []
    @Published var selectedIndex: Int = 0
    /// Max height of the AI answer scroll area, derived from screen geometry.
    @Published var maxAnswerHeight: CGFloat = 360

    let apps: AppIndexer
    let ai: AskAIService
    let settings: SettingsStore
    let history: AIHistoryStore

    enum OverlayMode: Equatable {
        case none
        case history
        case historyDetail(AIHistoryEntry)
    }

    @Published private(set) var overlayMode: OverlayMode = .none

    private var prefixAskTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        apps: AppIndexer? = nil,
        ai: AskAIService? = nil,
        settings: SettingsStore? = nil,
        history: AIHistoryStore? = nil
    ) {
        let resolvedApps = apps ?? AppIndexer()
        let resolvedSettings = settings ?? .shared
        let resolvedHistory = history ?? .shared
        let resolvedAI = ai ?? AskAIService(settings: resolvedSettings, history: resolvedHistory)
        self.apps = resolvedApps
        self.ai = resolvedAI
        self.settings = resolvedSettings
        self.history = resolvedHistory
        resolvedApps.refresh()
        rebuildResults()

        resolvedApps.$apps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildResults()
            }
            .store(in: &cancellables)

        resolvedAI.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        resolvedHistory.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.overlayMode != .none {
                    self.rebuildResults()
                }
            }
            .store(in: &cancellables)
    }

    var isShowingAnswerPane: Bool {
        if ai.isAnswerMode { return true }
        if case .historyDetail = overlayMode { return true }
        return false
    }

    var isShowingHistoryList: Bool {
        overlayMode == .history
    }

    func resetForShow() {
        query = ""
        overlayMode = .none
        ai.exitAnswerMode()
        selectedIndex = 0
        // Rescan so installs/uninstalls since launch aren't stuck in memory.
        apps.refresh()
        rebuildResults()
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    func activateSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        activate(results[selectedIndex])
    }

    func activateIndex(_ index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
        activate(results[index])
    }

    func activate(_ result: SearchResult) {
        switch result {
        case .app(let app):
            // Dismiss immediately; don't wait for the target app to activate.
            NotificationCenter.default.post(name: .launcherShouldHide, object: nil)
            Task { @MainActor in
                apps.open(app)
            }
        case .calculator(_, _, let display):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(display, forType: .string)
            NotificationCenter.default.post(name: .launcherShouldHide, object: nil)
        case .askAI(let prompt):
            ai.ask(prompt)
        case .slashCommand(let command):
            query = "/\(command.primaryToken)"
        case .historyEntry(let entry):
            overlayMode = .historyDetail(entry)
        }
    }

    func handleReturn() {
        if isShowingAnswerPane {
            handleReturnInAnswerMode()
        } else {
            activateSelected()
        }
    }

    func handleReturnInAnswerMode() {
        let text: String
        if case .historyDetail(let entry) = overlayMode {
            text = entry.answer
        } else {
            text = ai.answer
        }
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NotificationCenter.default.post(name: .launcherShouldHide, object: nil)
    }

    func handleEscape() -> Bool {
        if case .historyDetail = overlayMode {
            overlayMode = .history
            rebuildResults()
            return true
        }
        if overlayMode == .history {
            query = ""
            return true
        }
        if ai.isAnswerMode {
            ai.exitAnswerMode()
            rebuildResults()
            return true // consumed — stay open
        }
        return false // hide panel
    }

    // MARK: - Routing

    private func handleQueryChange(from oldValue: String) {
        // TextField may re-assign the same string on Return; ignore that so
        // arrow selection isn't reset before activateSelected runs.
        guard query != oldValue else { return }

        if ai.isAnswerMode {
            ai.exitAnswerMode()
        }
        if case .historyDetail = overlayMode {
            overlayMode = .history
        }
        selectedIndex = 0
        rebuildResults()

        prefixAskTask?.cancel()
        if let prompt = Self.askPrefixPrompt(from: query) {
            // Debounce auto-ask on prefix so typing "? hello" doesn't fire every key
            let captured = prompt
            prefixAskTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                if Self.askPrefixPrompt(from: self.query) == captured, !captured.isEmpty {
                    self.ai.ask(captured)
                }
            }
        }
    }

    func rebuildResults() {
        if ai.isAnswerMode {
            results = []
            return
        }

        if let input = SlashInput.parse(query) {
            applySlashInput(input)
            return
        }

        overlayMode = .none
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if let prompt = Self.askPrefixPrompt(from: query) {
            if prompt.isEmpty {
                results = []
            } else {
                results = [.askAI(prompt: prompt)]
            }
            return
        }

        var built: [SearchResult] = []

        let isMath = CalculatorEngine.looksLikeMath(trimmed)
        if let calc = CalculatorEngine.evaluate(trimmed) {
            built.append(.calculator(expression: trimmed, value: calc.value, display: calc.display))
        }

        let appMatches = apps.search(query: trimmed, limit: 9)
        built.append(contentsOf: appMatches.map { .app($0) })

        if !trimmed.isEmpty && !isMath && appMatches.isEmpty {
            built.append(.askAI(prompt: trimmed))
        }

        results = built
        if selectedIndex >= results.count {
            selectedIndex = max(0, results.count - 1)
        }
    }

    private func applySlashInput(_ input: SlashInput) {
        if let command = SlashCommandRegistry.exact(token: input.token) {
            switch command.presentation {
            case .history:
                presentHistory(filter: input.remainder)
                return
            case .commandList:
                break
            }
        }

        overlayMode = .none
        results = SlashCommandRegistry.matching(token: input.token).map { .slashCommand($0) }
        if selectedIndex >= results.count {
            selectedIndex = max(0, results.count - 1)
        }
    }

    private func presentHistory(filter: String) {
        let items = history.matching(filter)
        results = items.map { .historyEntry($0) }
        if selectedIndex >= results.count {
            selectedIndex = max(0, results.count - 1)
        }

        if case .historyDetail(let current) = overlayMode,
           items.contains(where: { $0.id == current.id }) {
            overlayMode = .historyDetail(current)
        } else {
            overlayMode = .history
        }
    }

    static func askPrefixPrompt(from query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("?") {
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("ask ") {
            return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

extension Notification.Name {
    static let launcherShouldHide = Notification.Name("launcherShouldHide")
    static let launcherShowSettings = Notification.Name("launcherShowSettings")
}
