import Foundation

enum FuzzyMatcher {
    /// Returns a score (higher is better), or nil if no match.
    static func score(query: String, in text: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return 0 }

        let queryChars = Array(q.lowercased())
        let textChars = Array(text.lowercased())
        guard !queryChars.isEmpty else { return 0 }

        var qi = 0
        var firstMatch: Int?
        var lastMatch = -1
        var consecutive = 0
        var maxConsecutive = 0
        var score = 0

        for (ti, ch) in textChars.enumerated() {
            guard qi < queryChars.count else { break }
            if ch == queryChars[qi] {
                if firstMatch == nil { firstMatch = ti }
                if lastMatch == ti - 1 {
                    consecutive += 1
                    maxConsecutive = max(maxConsecutive, consecutive)
                } else {
                    consecutive = 1
                }
                // Prefer earlier matches and matches at word starts
                score += 10
                if ti == 0 || textChars[ti - 1].isWhitespace || textChars[ti - 1] == "-" || textChars[ti - 1] == "_" {
                    score += 15
                }
                lastMatch = ti
                qi += 1
            }
        }

        guard qi == queryChars.count else { return nil }

        // Bonus for prefix / substring
        let lowerText = text.lowercased()
        let lowerQuery = q.lowercased()
        if lowerText.hasPrefix(lowerQuery) {
            score += 100
        } else if lowerText.contains(lowerQuery) {
            score += 40
        }

        score += maxConsecutive * 5
        // Prefer shorter names
        score -= text.count / 4
        return score
    }
}
