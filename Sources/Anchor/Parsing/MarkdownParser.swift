import Foundation

/// A small block-level Markdown parser. It only needs to understand structure well
/// enough to cut a document into readable pieces; inline styling (bold, italics,
/// code, links) is handled by Foundation's Markdown support.
nonisolated enum MarkdownParser {
    static func parse(_ source: String) -> [Block] {
        var lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        stripFrontMatter(&lines)

        var blocks: [Block] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var item: (marker: String, level: Int, lines: [String])?
        var nextGroup = 0

        func append(_ kind: SegmentKind, _ text: AttributedString) {
            guard !String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            var group: Int?
            if kind.isListItem {
                if let last = blocks.last, last.kind.isListItem, let g = last.listGroup {
                    group = g
                } else {
                    group = nextGroup
                    nextGroup += 1
                }
            }
            blocks.append(Block(kind: kind, text: text, listGroup: group))
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            append(.paragraph, Inline.render(joinLines(paragraph)))
            paragraph.removeAll()
        }

        func flushQuote() {
            guard !quote.isEmpty else { return }
            var buffer: [String] = []
            for line in quote + [""] {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !buffer.isEmpty {
                        append(.quote, Inline.render(joinLines(buffer)))
                        buffer.removeAll()
                    }
                } else {
                    buffer.append(line)
                }
            }
            quote.removeAll()
        }

        func flushItem() {
            guard let current = item else { return }
            append(.listItem(marker: current.marker, level: current.level), Inline.render(joinLines(current.lines)))
            item = nil
        }

        func flushAll() {
            flushParagraph()
            flushQuote()
            flushItem()
        }

        var i = 0
        while i < lines.count {
            let line = lines[i].replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // HTML comments
            if trimmed.hasPrefix("<!--") {
                flushAll()
                while i < lines.count && !lines[i].contains("-->") { i += 1 }
                i += 1
                continue
            }

            // Fenced code. Kept exactly as written (spacing matters for diagrams), except that
            // the fence's own indentation is removed and tabs become spaces so columns line up.
            if let fence = trimmed.wholeMatch(of: /(`{3,}|~{3,})(.*)/) {
                flushAll()
                let marker = String(fence.1)
                let fenceCharacter = marker.first ?? "`"
                let info = String(fence.2).trimmingCharacters(in: .whitespaces)
                let indent = lines[i].prefix(while: { $0 == " " }).count
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    // A closing fence uses the same character, at least as many times, and nothing else.
                    if t.count >= marker.count, t.allSatisfy({ $0 == fenceCharacter }) { break }
                    code.append(expandTabs(dropIndent(lines[i], upTo: indent)))
                    i += 1
                }
                i += 1
                let language = info.split(separator: " ").first.map(String.init)
                append(.code(language: language), AttributedString(code.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushQuote()
                flushItem()
                i += 1
                continue
            }

            // Setext headings (a line of === or --- under a paragraph)
            if !paragraph.isEmpty, item == nil, quote.isEmpty {
                if trimmed.wholeMatch(of: /=+/) != nil {
                    let text = paragraph.joined(separator: " ")
                    paragraph.removeAll()
                    append(.heading(1), Inline.render(text))
                    i += 1
                    continue
                }
                if trimmed.wholeMatch(of: /-{2,}/) != nil {
                    let text = paragraph.joined(separator: " ")
                    paragraph.removeAll()
                    append(.heading(2), Inline.render(text))
                    i += 1
                    continue
                }
            }

            // Horizontal rule
            if trimmed.wholeMatch(of: /(\*\s*){3,}|(-\s*){3,}|(_\s*){3,}/) != nil {
                flushAll()
                i += 1
                continue
            }

            // ATX heading
            if let m = trimmed.wholeMatch(of: /(#{1,6})\s+(.*?)(\s+#+)?\s*/) {
                flushAll()
                append(.heading(m.1.count), Inline.render(String(m.2)))
                i += 1
                continue
            }

            // HTML table (<table> blocks inside Markdown)
            if trimmed.lowercased().contains("<table") {
                flushAll()
                var html: [String] = []
                while i < lines.count {
                    html.append(lines[i])
                    i += 1
                    if html[html.count - 1].lowercased().contains("</table>") { break }
                }
                if let data = htmlTable(html.joined(separator: "\n")) { blocks.append(.table(data)) }
                continue
            }

            // Markdown table
            if trimmed.hasPrefix("|") || (trimmed.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1])) {
                flushAll()
                var header: [AttributedString] = []
                var alignments: [TableData.Align] = []
                var rows: [[AttributedString]] = []
                if i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                    header = cells(trimmed).map(Inline.render)
                    alignments = cells(lines[i + 1]).map(alignment)
                    i += 2
                }
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, t.contains("|") else { break }
                    if !isTableSeparator(t) { rows.append(cells(t).map(Inline.render)) }
                    i += 1
                }
                if !header.isEmpty || !rows.isEmpty {
                    blocks.append(.table(TableData(header: header, rows: rows, alignments: alignments)))
                }
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushItem()
                var content = String(trimmed.dropFirst())
                while content.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    content = String(content.trimmingCharacters(in: .whitespaces).dropFirst())
                }
                if content.hasPrefix(" ") { content.removeFirst() }
                quote.append(content)
                i += 1
                continue
            } else if !quote.isEmpty {
                flushQuote()
            }

            // Link reference definitions and footnote definitions: skip
            if paragraph.isEmpty, trimmed.firstMatch(of: /^\[[^\]]+\]:\s*\S+/) != nil {
                i += 1
                continue
            }

            // List item
            if let m = line.wholeMatch(of: /(\s*)([-*+]|\d{1,9}[.)])\s+(.*)/) {
                flushParagraph()
                flushItem()
                let indent = m.1.count
                let level = min(indent / 2, 4)
                var marker = String(m.2)
                var text = String(m.3)
                if marker == "-" || marker == "*" || marker == "+" {
                    marker = ["•", "◦", "▪︎"][min(level, 2)]
                }
                if text.hasPrefix("[ ] ") {
                    marker = "☐"
                    text.removeFirst(4)
                } else if text.lowercased().hasPrefix("[x] ") {
                    marker = "☑︎"
                    text.removeFirst(4)
                }
                item = (marker, level, [text])
                i += 1
                continue
            }

            // Continuation of the current list item
            if item != nil {
                item?.lines.append(trimmed)
                i += 1
                continue
            }

            // Indented code block
            if paragraph.isEmpty, line.hasPrefix("    "), !(blocks.last?.kind.isListItem ?? false) {
                var code: [String] = []
                while i < lines.count {
                    let l = lines[i].replacingOccurrences(of: "\t", with: "    ")
                    if l.hasPrefix("    ") {
                        code.append(expandTabs(String(lines[i].dropFirst(lines[i].hasPrefix("\t") ? 1 : 4))))
                    } else if l.trimmingCharacters(in: .whitespaces).isEmpty {
                        code.append("")
                    } else {
                        break
                    }
                    i += 1
                }
                while code.last == "" { code.removeLast() }
                append(.code(language: nil), AttributedString(code.joined(separator: "\n")))
                continue
            }

            // Raw HTML lines: keep any text, drop the tags
            if trimmed.hasPrefix("<"), trimmed.firstMatch(of: /^<\/?[a-zA-Z][^>]*>/) != nil {
                let stripped = Inline.stripTags(trimmed).trimmingCharacters(in: .whitespaces)
                if stripped.isEmpty {
                    flushParagraph()
                } else {
                    paragraph.append(stripped)
                }
                i += 1
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushAll()
        return blocks
    }

    // MARK: - Helpers

    /// Tabs to spaces with 4-column tab stops, so tab-aligned text keeps its columns.
    static func expandTabs(_ line: String, tabSize: Int = 4) -> String {
        guard line.contains("\t") else { return line }
        var out = ""
        var column = 0
        for character in line {
            if character == "\t" {
                let count = tabSize - column % tabSize
                out += String(repeating: " ", count: count)
                column += count
            } else {
                out.append(character)
                column += 1
            }
        }
        return out
    }

    static func dropIndent(_ line: String, upTo count: Int) -> String {
        var remaining = count
        var result = Substring(line)
        while remaining > 0, result.first == " " {
            result = result.dropFirst()
            remaining -= 1
        }
        return String(result)
    }

    static func stripFrontMatter(_ lines: inout [String]) {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return }
        for j in 1..<min(lines.count, 200) {
            let t = lines[j].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." {
                lines.removeSubrange(0...j)
                return
            }
        }
    }

    /// Joins the lines of a paragraph. A line ending in two spaces or a backslash is a hard break.
    static func joinLines(_ lines: [String]) -> String {
        var out = ""
        for (k, line) in lines.enumerated() {
            let hardBreak = line.hasSuffix("  ") || line.hasSuffix("\\")
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasSuffix("\\") { t.removeLast() }
            out += t
            if k < lines.count - 1 { out += hardBreak ? "\n" : " " }
        }
        return out
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        return t.wholeMatch(of: /\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?/) != nil
    }

    /// Splits a table row into cells. Pipes escaped as `\|` or inside `code` stay in the cell.
    static func cells(_ row: String) -> [String] {
        var t = row.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var cells: [String] = []
        var current = ""
        var inCode = false
        var escaped = false
        for character in t {
            if escaped {
                if character != "|" { current.append("\\") }
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" { escaped = true; continue }
            if character == "`" { inCode.toggle() }
            if character == "|" && !inCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(character)
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    static func alignment(_ spec: String) -> TableData.Align {
        let t = spec.trimmingCharacters(in: .whitespaces)
        let left = t.hasPrefix(":")
        let right = t.hasSuffix(":")
        if left && right { return .center }
        return right ? .trailing : .leading
    }

    static func htmlTable(_ html: String) -> TableData? {
        var header: [AttributedString] = []
        var rows: [[AttributedString]] = []
        for row in html.matches(of: /(?is)<tr[^>]*>(.*?)<\/tr>/) {
            var cells: [AttributedString] = []
            var allHeaderCells = true
            for cell in String(row.1).matches(of: /(?is)<(th|td)[^>]*>(.*?)<\/(?:th|td)>/) {
                if String(cell.1).lowercased() != "th" { allHeaderCells = false }
                cells.append(Inline.render(htmlCellText(String(cell.2))))
            }
            guard !cells.isEmpty else { continue }
            if header.isEmpty && rows.isEmpty && allHeaderCells {
                header = cells
            } else {
                rows.append(cells)
            }
        }
        guard !header.isEmpty || !rows.isEmpty else { return nil }
        return TableData(header: header, rows: rows)
    }

    static func htmlCellText(_ html: String) -> String {
        var t = html.replacing(/(?i)<\/?(b|strong)>/, with: "**")
        t = t.replacing(/(?i)<\/?(i|em)>/, with: "*")
        t = t.replacing(/(?i)<br\s*\/?>/, with: " ")
        t = Inline.stripTags(t)
        let entities = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
        for (entity, character) in entities { t = t.replacingOccurrences(of: entity, with: character) }
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Inline Markdown → AttributedString.
nonisolated enum Inline {
    static func render(_ source: String) -> AttributedString {
        let text = preprocess(source)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }

    static func preprocess(_ s: String) -> String {
        var t = s
        // Images become a short text placeholder; there's nothing to read in them.
        t = t.replacing(/!\[([^\]]*)\]\([^)]*\)/) { match in
            let alt = String(match.1).trimmingCharacters(in: .whitespaces)
            return alt.isEmpty ? "[image]" : "[image: \(alt)]"
        }
        t = t.replacing(/<br\s*\/?>/.ignoresCase(), with: "\n")
        t = stripTags(t)
        return t
    }

    static func stripTags(_ s: String) -> String {
        s.replacing(/<\/?[a-zA-Z][^>]*>/, with: "")
    }
}
