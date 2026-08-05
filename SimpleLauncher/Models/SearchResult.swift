import AppKit
import Foundation

enum SearchResult: Identifiable, Equatable {
    case app(AppEntry)
    case calculator(expression: String, value: Double, display: String)
    case askAI(prompt: String)

    var id: String {
        switch self {
        case .app(let app):
            return "app:\(app.url.path)"
        case .calculator(let expression, _, let display):
            return "calc:\(expression)=\(display)"
        case .askAI(let prompt):
            return "ai:\(prompt)"
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
        }
    }
}

struct AppEntry: Equatable, Hashable {
    let name: String
    let url: URL
    let bundleIdentifier: String?

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
