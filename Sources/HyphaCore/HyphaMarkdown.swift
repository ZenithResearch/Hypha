import Foundation

public enum HyphaMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedListItem(String)
    case orderedListItem(number: Int, text: String)
    case quote(String)
    case codeBlock(language: String?, code: String)
    case horizontalRule
}

public enum HyphaMarkdownParser {
    public static func blocks(in source: String) -> [HyphaMarkdownBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [HyphaMarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeFence: String?
        var codeLanguage: String?
        var codeLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
            codeFence = nil
            codeLanguage = nil
            codeLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let codeFence {
                if trimmed.hasPrefix(codeFence) {
                    flushCode()
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                codeFence = fence
                let language = String(trimmed.dropFirst(fence.count))
                    .trimmingCharacters(in: .whitespaces)
                codeLanguage = language.isEmpty ? nil : language
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(.horizontalRule)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let text = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(text))
                continue
            }

            if let item = unorderedListItem(from: trimmed) {
                flushParagraph()
                blocks.append(.unorderedListItem(item))
                continue
            }

            if let item = orderedListItem(from: trimmed) {
                flushParagraph()
                blocks.append(item)
                continue
            }

            paragraphLines.append(trimmed)
        }

        if codeFence != nil {
            flushCode()
        }
        flushParagraph()
        return blocks
    }

    private static func heading(from line: String) -> HyphaMarkdownBlock? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level),
              line.index(line.startIndex, offsetBy: level) < line.endIndex,
              line[line.index(line.startIndex, offsetBy: level)] == " " else {
            return nil
        }
        let text = String(line.dropFirst(level + 1))
            .trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    private static func unorderedListItem(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedListItem(from line: String) -> HyphaMarkdownBlock? {
        guard let separator = line.firstIndex(of: ".") else { return nil }
        let numberText = String(line[..<separator])
        guard let number = Int(numberText), number > 0 else { return nil }
        let afterSeparator = line.index(after: separator)
        guard afterSeparator < line.endIndex, line[afterSeparator] == " " else { return nil }
        let text = String(line[line.index(after: afterSeparator)...])
        return .orderedListItem(number: number, text: text)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first, ["-", "*", "_"].contains(marker) else {
            return false
        }
        return compact.allSatisfy { $0 == marker }
    }
}
