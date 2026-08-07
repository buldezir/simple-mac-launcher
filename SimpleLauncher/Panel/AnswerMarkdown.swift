import AppKit
import SwiftUI

/// Lightweight markdown → AttributedString for the answer pane.
/// Avoids `AttributedString(markdown:)` which collapses newlines around links.
enum AnswerMarkdown {
    private static let urlRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"https?://[^\s<>\[\]()\"'`]+"#,
            options: []
        )
    }()

    static func attributedString(from markdown: String) -> AttributedString {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else { return AttributedString() }

        var result = AttributedString()
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var inFence = false

        for (index, lineSub) in lines.enumerated() {
            let line = String(lineSub)
            if line.hasPrefix("```") {
                inFence.toggle()
            } else if inFence {
                result.append(autolinkPlain(line, monospaced: true))
            } else {
                result.append(renderLine(line))
            }
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private static func renderLine(_ line: String) -> AttributedString {
        if line.hasPrefix("### ") {
            return heading(String(line.dropFirst(4)))
        }
        if line.hasPrefix("## ") {
            return heading(String(line.dropFirst(3)))
        }
        if line.hasPrefix("# ") {
            return heading(String(line.dropFirst(2)))
        }

        var result = AttributedString()
        var content = line
        if content.hasPrefix("- ") || content.hasPrefix("* ") {
            result.append(AttributedString("• "))
            content = String(content.dropFirst(2))
        } else if let ordered = content.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            result.append(AttributedString(String(content[ordered])))
            content = String(content[ordered.upperBound...])
        }
        result.append(renderInline(content))
        return result
    }

    private static func heading(_ text: String) -> AttributedString {
        var heading = renderInline(text)
        heading.font = .system(size: 14, weight: .semibold)
        return heading
    }

    private static func renderInline(_ text: String) -> AttributedString {
        var result = AttributedString()
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "`",
               let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let codeText = String(text[text.index(after: index)..<end])
                if looksLikeURL(codeText), let url = URL(string: trimTrailingPunctuation(codeText).url) {
                    result.append(styledLink(label: codeText, url: url))
                } else {
                    var code = AttributedString(codeText)
                    code.font = .system(.body, design: .monospaced)
                    code.backgroundColor = Color.primary.opacity(0.08)
                    result.append(code)
                }
                index = text.index(after: end)
                continue
            }

            if text[index...].hasPrefix("**"),
               let endRange = text.range(of: "**", range: text.index(index, offsetBy: 2)..<text.endIndex) {
                let inner = String(text[text.index(index, offsetBy: 2)..<endRange.lowerBound])
                var bold = renderInline(inner)
                bold.font = .system(size: 14, weight: .semibold)
                result.append(bold)
                index = endRange.upperBound
                continue
            }

            if text[index] == "[",
               let link = parseLink(in: text, from: index) {
                if let url = URL(string: link.url) {
                    result.append(styledLink(label: link.label, url: url))
                } else {
                    result.append(AttributedString(link.label))
                }
                index = link.endIndex
                continue
            }

            let specials: Set<Character> = ["`", "*", "["]
            var end = index
            while end < text.endIndex, !specials.contains(text[end]) {
                end = text.index(after: end)
            }
            if end == index {
                result.append(AttributedString(String(text[index])))
                index = text.index(after: index)
            } else {
                result.append(autolinkPlain(String(text[index..<end]), monospaced: false))
                index = end
            }
        }

        return result
    }

    private static func autolinkPlain(_ text: String, monospaced: Bool) -> AttributedString {
        guard let regex = urlRegex else {
            var plain = AttributedString(text)
            if monospaced { plain.font = .system(.body, design: .monospaced) }
            return plain
        }

        var result = AttributedString()
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var cursor = 0

        for match in regex.matches(in: text, options: [], range: full) {
            if match.range.location > cursor {
                let before = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                var plain = AttributedString(before)
                if monospaced { plain.font = .system(.body, design: .monospaced) }
                result.append(plain)
            }

            let raw = ns.substring(with: match.range)
            let trimmed = trimTrailingPunctuation(raw)
            if let url = URL(string: trimmed.url) {
                result.append(styledLink(label: trimmed.url, url: url))
                if !trimmed.trailing.isEmpty {
                    var trail = AttributedString(trimmed.trailing)
                    if monospaced { trail.font = .system(.body, design: .monospaced) }
                    result.append(trail)
                }
            } else {
                var plain = AttributedString(raw)
                if monospaced { plain.font = .system(.body, design: .monospaced) }
                result.append(plain)
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            var plain = AttributedString(ns.substring(from: cursor))
            if monospaced { plain.font = .system(.body, design: .monospaced) }
            result.append(plain)
        }

        return result
    }

    private static func styledLink(label: String, url: URL) -> AttributedString {
        var linkText = AttributedString(label)
        linkText.link = url
        linkText.foregroundColor = Color.accentColor
        linkText.underlineStyle = .single
        return linkText
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    /// Strip trailing punctuation commonly stuck to URLs in prose.
    private static func trimTrailingPunctuation(_ raw: String) -> (url: String, trailing: String) {
        var url = raw
        var trailing = ""
        while let last = url.last, ".,);:]>".contains(last) {
            trailing = String(last) + trailing
            url.removeLast()
        }
        return (url, trailing)
    }

    private static func parseLink(in text: String, from start: String.Index) -> (label: String, url: String, endIndex: String.Index)? {
        guard text[start] == "[",
              let labelEnd = text[text.index(after: start)...].firstIndex(of: "]"),
              labelEnd < text.endIndex
        else { return nil }

        let afterLabel = text.index(after: labelEnd)
        guard afterLabel < text.endIndex, text[afterLabel] == "(",
              let urlEnd = text[text.index(after: afterLabel)...].firstIndex(of: ")")
        else { return nil }

        let label = String(text[text.index(after: start)..<labelEnd])
        let url = String(text[text.index(after: afterLabel)..<urlEnd])
        guard !label.isEmpty, !url.isEmpty else { return nil }
        return (label, url, text.index(after: urlEnd))
    }
}
