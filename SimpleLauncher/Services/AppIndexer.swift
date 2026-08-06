import AppKit
import Foundation

@MainActor
final class AppIndexer: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []

    private var isIndexing = false

    func refresh() {
        guard !isIndexing else { return }
        isIndexing = true
        Task.detached(priority: .utility) { [weak self] in
            let scanned = Self.scanApps()
            await MainActor.run {
                self?.apps = scanned
                self?.isIndexing = false
            }
        }
    }

    func search(query: String, limit: Int = 9) -> [AppEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let scored: [(AppEntry, Int)] = apps.compactMap { app in
            guard let score = FuzzyMatcher.score(query: trimmed, in: app.name) else { return nil }
            return (app, score)
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    func open(_ app: AppEntry) {
        NSWorkspace.shared.open(app.url)
    }

    nonisolated private static func scanApps() -> [AppEntry] {
        let directories = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications",
        ]

        var seen = Set<String>()
        var results: [AppEntry] = []

        for dir in directories {
            let url = URL(fileURLWithPath: dir)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let item as URL in enumerator {
                guard item.pathExtension == "app" else { continue }

                let path = item.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                results.append(
                    AppEntry(
                        name: item.deletingPathExtension().lastPathComponent,
                        url: item
                    )
                )
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
