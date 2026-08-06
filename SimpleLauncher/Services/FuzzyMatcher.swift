import Foundation

enum FuzzyMatcher {
    /// Returns a score (higher is better), or nil if no match.
    ///
    /// Matches when the query is a contiguous substring, or when characters
    /// align with word/camelCase starts (gaps may only land on those boundaries).
    static func score(query: String, in text: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return 0 }

        let lowerQuery = q.lowercased()
        let lowerText = text.lowercased()
        let queryChars = Array(lowerQuery)
        let textChars = Array(lowerText)
        let originalChars = Array(text)
        guard !queryChars.isEmpty else { return 0 }

        // Contiguous substring is the strongest signal.
        if let range = lowerText.range(of: lowerQuery) {
            let start = lowerText.distance(from: lowerText.startIndex, to: range.lowerBound)
            var score = 80 + max(0, 40 - start * 2)
            if start == 0 { score += 60 }
            score -= text.count / 4
            return score
        }

        var qi = 0
        var firstMatch: Int?
        var lastMatch = -2
        var consecutive = 0
        var maxConsecutive = 0
        var score = 0
        var matchedWordStarts = 0

        for (ti, ch) in textChars.enumerated() {
            guard qi < queryChars.count else { break }
            guard ch == queryChars[qi] else { continue }

            let isConsecutive = lastMatch == ti - 1
            let isWordStart = Self.isWordStart(at: ti, in: originalChars)

            // New match runs (including the first) must start on a word boundary.
            // Continuing a run may consume mid-word characters.
            if !isConsecutive && !isWordStart {
                continue
            }

            if firstMatch == nil { firstMatch = ti }
            if isConsecutive {
                consecutive += 1
            } else {
                consecutive = 1
                matchedWordStarts += 1
            }
            maxConsecutive = max(maxConsecutive, consecutive)

            score += 10
            if isWordStart { score += 15 }
            if isConsecutive { score += 8 }

            lastMatch = ti
            qi += 1
        }

        guard qi == queryChars.count else { return nil }

        score += maxConsecutive * 5
        score += matchedWordStarts * 10
        if firstMatch == 0 { score += 20 }
        score -= text.count / 4
        return score
    }

    private static func isWordStart(at index: Int, in chars: [Character]) -> Bool {
        if index == 0 { return true }
        let prev = chars[index - 1]
        let current = chars[index]
        if prev.isWhitespace || prev == "-" || prev == "_" || prev == "." || prev == "/" {
            return true
        }
        // camelCase / PascalCase boundary: "DaVinci" → V
        if prev.isLowercase && current.isUppercase { return true }
        if prev.isNumber && current.isLetter { return true }
        if prev.isLetter && current.isNumber { return true }
        return false
    }
}
