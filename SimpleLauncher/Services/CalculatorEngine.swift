import Foundation

enum CalculatorEngine {
    /// Returns a formatted result if `query` looks like a math expression.
    static func evaluate(_ query: String) -> (value: Double, display: String)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeMath(trimmed) else { return nil }
        do {
            var parser = ExpressionParser(normalize(trimmed))
            let value = try parser.parseExpression()
            guard value.isFinite else { return nil }
            return (value, format(value))
        } catch {
            return nil
        }
    }

    static func looksLikeMath(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.contains(where: \.isASCIIDigit) else { return false }

        let allowed: Set<Character> = Set("0123456789.+-*/()%^ \t×÷−")
        let letters = CharacterSet.letters
        guard trimmed.unicodeScalars.allSatisfy({
            allowed.contains(Character($0)) || letters.contains($0)
        }) else { return false }

        let lower = trimmed.lowercased()
        let hasOp = trimmed.contains(where: { "+-*/%^()×÷−".contains($0) })
            || lower.contains("sqrt")
            || lower.contains("% of ")
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        let isPlainNumber = Double(normalized) != nil
        return hasOp || isPlainNumber
    }

    private static func normalize(_ input: String) -> String {
        var s = input.replacingOccurrences(of: ",", with: "")
        s = s.replacingOccurrences(of: "×", with: "*")
        s = s.replacingOccurrences(of: "÷", with: "/")
        s = s.replacingOccurrences(of: "−", with: "-")
        s = s.replacingOccurrences(of: "＋", with: "+")

        // "50% of 80" → "80*50%"
        let ofPattern = #/(?i)(\d+(?:\.\d+)?)\s*%\s*of\s*(\d+(?:\.\d+)?)/#
        while let match = s.firstMatch(of: ofPattern) {
            s.replaceSubrange(match.range, with: "\(match.2)*\(match.1)%")
        }

        // sqrt(x) → evaluated constant
        while let range = s.range(of: #"(?i)sqrt\s*\("#, options: .regularExpression) {
            let openIndex = s.index(before: range.upperBound)
            guard let close = findMatchingParen(in: s, openAt: openIndex) else { break }
            let inner = String(s[range.upperBound..<close])
            var parser = ExpressionParser(normalize(inner))
            guard let value = try? parser.parseExpression() else { break }
            s.replaceSubrange(range.lowerBound...close, with: formatRaw(sqrt(value)))
        }

        return s
    }

    private static func findMatchingParen(in s: String, openAt: String.Index) -> String.Index? {
        var depth = 0
        var i = openAt
        while i < s.endIndex {
            if s[i] == "(" { depth += 1 }
            if s[i] == ")" {
                depth -= 1
                if depth == 0 { return i }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        var s = String(format: "%.10f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func formatRaw(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(value)
    }
}

// MARK: - Recursive-descent parser

private struct ExpressionParser {
    enum ParseError: Error { case invalid }

    private let chars: [Character]
    private var index = 0

    init(_ input: String) {
        self.chars = Array(input.filter { !$0.isWhitespace })
    }

    mutating func parseExpression() throws -> Double {
        let value = try parseAddSub()
        guard index >= chars.count else { throw ParseError.invalid }
        return value
    }

    /// addition / subtraction, with percent semantics: a±b% → a ± a*(b/100)
    private mutating func parseAddSub() throws -> Double {
        var left = try parseMulDiv()

        while let op = peek(), op == "+" || op == "-" {
            advance()
            let (right, rightIsPercent) = try parseMulDivValue()
            if rightIsPercent {
                let factor = right / 100.0
                left = (op == "+") ? (left + left * factor) : (left - left * factor)
            } else {
                left = (op == "+") ? (left + right) : (left - right)
            }
        }
        return left
    }

    private mutating func parseMulDiv() throws -> Double {
        let (value, isPercent) = try parseMulDivValue()
        if isPercent {
            // Standalone percent at start of mul/div term (e.g. "20%")
            return value / 100.0
        }
        return value
    }

    /// Returns the numeric magnitude and whether it was a percent term (e.g. 20%).
    private mutating func parseMulDivValue() throws -> (Double, Bool) {
        var (left, leftIsPercent) = try parsePower()

        while let op = peek(), op == "*" || op == "/" {
            advance()
            let (right, rightIsPercent) = try parsePower()
            let r = rightIsPercent ? right / 100.0 : right
            let l = leftIsPercent ? left / 100.0 : left
            guard !(op == "/" && r == 0) else { throw ParseError.invalid }
            left = (op == "*") ? (l * r) : (l / r)
            leftIsPercent = false
        }

        return (left, leftIsPercent)
    }

    private mutating func parsePower() throws -> (Double, Bool) {
        let (base, baseIsPercent) = try parseUnary()

        if peek() == "^" {
            advance()
            let (exp, expIsPercent) = try parseUnary()
            let b = baseIsPercent ? base / 100.0 : base
            let e = expIsPercent ? exp / 100.0 : exp
            return (pow(b, e), false)
        }

        return (base, baseIsPercent)
    }

    private mutating func parseUnary() throws -> (Double, Bool) {
        if peek() == "+" {
            advance()
            return try parseUnary()
        }
        if peek() == "-" {
            advance()
            let (value, isPercent) = try parseUnary()
            return (-value, isPercent)
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> (Double, Bool) {
        if peek() == "(" {
            advance()
            let value = try parseAddSub()
            guard peek() == ")" else { throw ParseError.invalid }
            advance()
            // (expr)% 
            if peek() == "%" {
                advance()
                return (value, true)
            }
            return (value, false)
        }
        return try parseNumber()
    }

    private mutating func parseNumber() throws -> (Double, Bool) {
        guard let c = peek(), c.isASCIIDigit || c == "." else {
            throw ParseError.invalid
        }

        var buf = ""
        while let d = peek(), d.isASCIIDigit {
            buf.append(d)
            advance()
        }
        if peek() == "." {
            buf.append(".")
            advance()
            guard peek()?.isASCIIDigit == true else { throw ParseError.invalid }
            while let d = peek(), d.isASCIIDigit {
                buf.append(d)
                advance()
            }
        }

        guard let value = Double(buf) else { throw ParseError.invalid }
        if peek() == "%" {
            advance()
            return (value, true)
        }
        return (value, false)
    }

    private func peek() -> Character? {
        guard index < chars.count else { return nil }
        return chars[index]
    }

    private mutating func advance() {
        index += 1
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
