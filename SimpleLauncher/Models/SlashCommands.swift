import Foundation

/// Parsed `/token remainder` from the search field.
struct SlashInput: Equatable {
    /// Command token without the leading `/`, lowercased. Empty when the query is just `/`.
    let token: String
    /// Text after the token, used as an argument (e.g. history filter).
    let remainder: String

    static func parse(_ query: String) -> SlashInput? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else {
            return SlashInput(token: "", remainder: "")
        }

        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let token = String(parts[0]).lowercased()
        let remainder = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return SlashInput(token: token, remainder: remainder)
    }
}

/// How a resolved command is presented in the launcher.
/// Add a case when a new command needs its own pane or behavior.
enum SlashPresentation: Equatable {
    /// Show matching commands in the results list.
    case commandList
    /// Show the AI history pane, optionally filtered by `remainder`.
    case history
}

/// A slash command. Register new ones on `SlashCommandRegistry.all`.
struct SlashCommand: Equatable, Identifiable {
    let id: String
    /// Tokens that invoke this command (`h`, `history`). First token is the short form.
    let tokens: [String]
    let title: String
    let subtitle: String
    let systemImage: String
    let presentation: SlashPresentation

    var primaryToken: String { tokens[0] }

    var resultTitle: String { "/\(primaryToken)  \(title)" }
}

enum SlashCommandRegistry {
    /// All built-in commands. Append here to add more.
    static let all: [SlashCommand] = [
        SlashCommand(
            id: "history",
            tokens: ["h", "history"],
            title: "History",
            subtitle: "Recent AI queries and answers",
            systemImage: "clock",
            presentation: .history
        ),
    ]

    static func matching(token: String) -> [SlashCommand] {
        let t = token.lowercased()
        if t.isEmpty { return all }
        return all.filter { command in
            command.tokens.contains { $0.hasPrefix(t) }
        }
    }

    /// Full token match (`/h`, `/history`), not merely a prefix (`/hi`).
    static func exact(token: String) -> SlashCommand? {
        let t = token.lowercased()
        guard !t.isEmpty else { return nil }
        return all.first { $0.tokens.contains(t) }
    }

    static func command(id: String) -> SlashCommand? {
        all.first { $0.id == id }
    }
}
