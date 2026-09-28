import Foundation

/// Strips common markdown from LLM replies for plain-text chat bubbles.
enum ChatResponseFormatter {
    static func plainText(from raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        text = stripInlineMarkdown(text)
        text = stripLinePrefixes(text)
        text = collapseBlankLines(text)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripInlineMarkdown(_ text: String) -> String {
        var result = text

        let patterns: [(String, String)] = [
            (#"\*\*\*(.+?)\*\*\*"#, "$1"),
            (#"___(.+?)___"#, "$1"),
            (#"\*\*(.+?)\*\*"#, "$1"),
            (#"__(.+?)__"#, "$1"),
            (#"`([^`]+)`"#, "$1"),
            (#"\[([^\]]+)\]\([^)]+\)"#, "$1"),
            (#"^>\s?"#, ""),
        ]

        for (pattern, template) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }

        return result
    }

    private static func stripLinePrefixes(_ text: String) -> String {
        let headerPattern = #"^\s{0,3}#{1,6}\s+"#
        let bulletPattern = #"^\s{0,3}[-*+]\s+"#
        let orderedPattern = #"^\s{0,3}\d+\.\s+"#

        return text
            .components(separatedBy: "\n")
            .map { line in
                var cleaned = line
                for pattern in [headerPattern, bulletPattern, orderedPattern] {
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
                       let range = Range(match.range, in: cleaned) {
                        cleaned.removeSubrange(range)
                    }
                }
                cleaned = cleaned.replacingOccurrences(of: "---", with: "")
                return cleaned.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }

    private static func collapseBlankLines(_ text: String) -> String {
        text
            .components(separatedBy: "\n")
            .reduce(into: [String]()) { lines, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    if lines.last?.isEmpty != true { lines.append("") }
                } else {
                    lines.append(trimmed)
                }
            }
            .joined(separator: "\n")
    }
}
