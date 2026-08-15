import AppKit
import Foundation

enum SearchResult: Identifiable, Equatable {
    case app(AppEntry)
    case calculator(expression: String, value: Double, display: String)
    case askAI(prompt: String)
    case slashCommand(SlashCommand)
    case historyEntry(AIHistoryEntry)

    var id: String {
        switch self {
        case .app(let app):
            return "app:\(app.url.path)"
        case .calculator(let expression, _, let display):
            return "calc:\(expression)=\(display)"
        case .askAI(let prompt):
            return "ai:\(prompt)"
        case .slashCommand(let command):
            return "slash:\(command.id)"
        case .historyEntry(let entry):
            return "hist:\(entry.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .app(let app):
            return app.name
        case .calculator(_, _, let display):
            return "= \(display)"
        case .askAI(let prompt):
            return "Ask AI: \(prompt)"
        case .slashCommand(let command):
            return command.resultTitle
        case .historyEntry(let entry):
            return entry.prompt
        }
    }

    var subtitle: String? {
        switch self {
        case .app(let app):
            return app.url.deletingLastPathComponent().path
        case .calculator(let expression, _, _):
            return expression
        case .askAI:
            return "Send to configured AI endpoint"
        case .slashCommand(let command):
            return command.subtitle
        case .historyEntry(let entry):
            let preview = entry.answerPreview
            return preview.isEmpty ? entry.relativeDate : "\(entry.relativeDate) · \(preview)"
        }
    }
}

struct AppEntry: Equatable, Hashable {
    let name: String
    let url: URL

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
