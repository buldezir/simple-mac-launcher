import Combine
import Foundation

struct AIHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let prompt: String
    let answer: String
    let createdAt: Date

    var answerPreview: String {
        let collapsed = answer
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 90 { return collapsed }
        return String(collapsed.prefix(90)) + "…"
    }

    var relativeDate: String {
        RelativeDateTimeFormatter.launcher.localizedString(for: createdAt, relativeTo: Date())
    }
}

private extension RelativeDateTimeFormatter {
    static let launcher: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

@MainActor
final class AIHistoryStore: ObservableObject {
    static let shared = AIHistoryStore()
    private static let storageKey = "ai.history"
    private static let maxAnswerChars = 32_768

    @Published private(set) var entries: [AIHistoryEntry] = []

    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        load()
        settings.$aiHistoryLimit
            .dropFirst()
            .sink { [weak self] _ in
                self?.trimToLimit(persistIfChanged: true)
            }
            .store(in: &cancellables)
    }

    func record(prompt: String, answer: String) {
        guard settings.aiHistoryLimit > 0 else { return }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !trimmedAnswer.isEmpty else { return }

        let cappedAnswer = trimmedAnswer.count > Self.maxAnswerChars
            ? String(trimmedAnswer.prefix(Self.maxAnswerChars))
            : trimmedAnswer

        let entry = AIHistoryEntry(
            id: UUID(),
            prompt: trimmedPrompt,
            answer: cappedAnswer,
            createdAt: Date()
        )
        entries.insert(entry, at: 0)
        trimToLimit(persistIfChanged: false)
        persist()
    }

    func entry(id: UUID) -> AIHistoryEntry? {
        entries.first { $0.id == id }
    }

    func matching(_ filter: String) -> [AIHistoryEntry] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.prompt.localizedCaseInsensitiveContains(trimmed)
                || $0.answer.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([AIHistoryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
        trimToLimit(persistIfChanged: true)
    }

    private func trimToLimit(persistIfChanged: Bool) {
        let limit = max(0, settings.aiHistoryLimit)
        let trimmed = Array(entries.prefix(limit))
        guard trimmed != entries else { return }
        entries = trimmed
        if persistIfChanged {
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
