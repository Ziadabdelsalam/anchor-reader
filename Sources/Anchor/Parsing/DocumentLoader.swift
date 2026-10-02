import AppKit
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers

enum DocumentLoader {
    nonisolated static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "txt", "text"]
    nonisolated static let richExtensions: Set<String> = ["docx", "doc", "rtf", "rtfd", "html", "htm", "odt", "webarchive"]

    static var contentTypes: [UTType] {
        var types: [UTType] = [.plainText, .pdf, .rtf, .rtfd, .html, .webArchive]
        for ext in ["md", "markdown", "docx", "doc", "odt"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    static func load(_ url: URL) async throws -> LoadedDocument {
        let ext = url.pathExtension.lowercased()
        var doc: LoadedDocument
        if richExtensions.contains(ext) {
            // NSAttributedString's importers (HTML especially) must run on the main thread.
            doc = try RichTextImporter.load(url)
        } else if ext == "pdf" {
            doc = try await Task.detached(priority: .userInitiated) { try PDFImporter.load(url) }.value
        } else if markdownExtensions.contains(ext) || ext.isEmpty {
            doc = try await Task.detached(priority: .userInitiated) { try MarkdownImporter.load(url) }.value
        } else {
            throw LoadError.unsupported(ext)
        }
        guard !doc.blocks.isEmpty else { throw LoadError.noText }
        doc.language = detectLanguage(doc.blocks)
        return doc
    }

    nonisolated static func detectLanguage(_ blocks: [Block]) -> String? {
        let sample = blocks.prefix(60).map { String($0.text.characters) }.joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample.prefix(4000)))
        return recognizer.dominantLanguage?.rawValue
    }
}

nonisolated enum MarkdownImporter {
    static func load(_ url: URL) throws -> LoadedDocument {
        let text = try readText(url)
        let blocks = MarkdownParser.parse(text)
        let firstH1 = blocks.first { $0.kind == .heading(1) }.map { String($0.text.characters) }
        return LoadedDocument(title: firstH1 ?? url.deletingPathExtension().lastPathComponent, blocks: blocks)
    }

    static func readText(_ url: URL) throws -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        var encoding = String.Encoding.utf8
        if let s = try? String(contentsOf: url, usedEncoding: &encoding) { return s }
        if let s = try? String(contentsOf: url, encoding: .isoLatin1) { return s }
        throw LoadError.unreadable
    }
}

/// PDFs don't store paragraphs, only positioned lines. This rebuilds paragraphs and
/// headings with a few heuristics that work well for papers and reports.
nonisolated enum PDFImporter {
    static func load(_ url: URL) throws -> LoadedDocument {
        guard let pdf = PDFDocument(url: url) else { throw LoadError.unreadable }
        if pdf.isLocked { throw LoadError.locked }

        var pages: [[String]] = []
        for p in 0..<pdf.pageCount {
            guard let text = pdf.page(at: p)?.string else { continue }
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            pages.append(lines)
        }

        let noise = repeatedHeaderFooterLines(pages)
        let lines = pages.flatMap { page in
            page.filter { line in
                !isPageNumber(line) && !noise.contains(normalized(line))
            }
        }
        let blocks = buildBlocks(lines)
        guard !blocks.isEmpty else { throw LoadError.noText }

        let metaTitle = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespaces)
        let title = (metaTitle?.isEmpty == false ? metaTitle : nil) ?? url.deletingPathExtension().lastPathComponent
        return LoadedDocument(title: title, blocks: blocks)
    }

    static func normalized(_ line: String) -> String {
        line.lowercased().replacing(/\d+/, with: "#")
    }

    static func isPageNumber(_ line: String) -> Bool {
        line.wholeMatch(of: /(?i)(page\s*)?\d{1,4}(\s*(of|\/)\s*\d{1,4})?/) != nil
    }

    /// Running heads and footers repeat on most pages; drop them.
    static func repeatedHeaderFooterLines(_ pages: [[String]]) -> Set<String> {
        guard pages.count >= 4 else { return [] }
        var counts: [String: Int] = [:]
        for page in pages {
            let edges = Set((page.prefix(2) + page.suffix(2)).map(normalized))
            for e in edges { counts[e, default: 0] += 1 }
        }
        let threshold = max(3, Int(Double(pages.count) * 0.3))
        return Set(counts.filter { $0.value >= threshold }.keys)
    }

    static func buildBlocks(_ lines: [String]) -> [Block] {
        let lengths = lines.map(\.count).sorted()
        let typical = lengths.isEmpty ? 80 : max(30, lengths[min(lengths.count - 1, Int(Double(lengths.count) * 0.75))])

        var blocks: [Block] = []
        var current = ""
        var currentIsBullet = false

        func flush() {
            let t = current.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                if currentIsBullet {
                    var text = t
                    if let first = text.first, "•◦▪●–-".contains(first) {
                        text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                    }
                    let group = (blocks.last?.kind.isListItem ?? false) ? blocks.last?.listGroup : (blocks.compactMap(\.listGroup).max() ?? -1) + 1
                    blocks.append(Block(kind: .listItem(marker: "•", level: 0), text: AttributedString(text), listGroup: group))
                } else {
                    blocks.append(Block(kind: .paragraph, text: AttributedString(t)))
                }
            }
            current = ""
            currentIsBullet = false
        }

        for line in lines {
            let startsBullet = line.first.map { "•◦▪●".contains($0) } ?? false
            if current.isEmpty, let level = headingLevel(line, typical: typical) {
                blocks.append(Block(kind: .heading(level), text: AttributedString(line)))
                continue
            }
            if startsBullet {
                flush()
                currentIsBullet = true
            }
            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-"), current.dropLast().last?.isLetter == true, line.first?.isLowercase == true {
                current.removeLast()
                current += line
            } else {
                current += " " + line
            }
            // A short line that ends a sentence is usually the last line of a paragraph.
            if Double(line.count) < Double(typical) * 0.72, let last = line.last, ".!?:\"”')]".contains(last) {
                flush()
            }
        }
        flush()
        return blocks
    }

    static let knownHeadings: Set<String> = [
        "abstract", "introduction", "background", "related work", "method", "methods", "methodology",
        "materials and methods", "results", "discussion", "general discussion", "conclusion", "conclusions",
        "references", "bibliography", "acknowledgments", "acknowledgements", "appendix", "summary",
        "limitations", "future work", "literature review", "keywords", "highlights", "experiment 1",
        "experiment 2", "experiment 3", "procedure", "participants", "materials", "design",
    ]

    static func headingLevel(_ line: String, typical: Int) -> Int? {
        guard line.count >= 3, line.count <= 90, Double(line.count) < Double(typical) * 0.85 else { return nil }
        let words = line.split(separator: " ")
        guard words.count <= 12 else { return nil }

        // "2.1 Participants" or, in legal documents, "1. General."
        if let m = line.wholeMatch(of: /(\d{1,2}(?:\.\d{1,2}){0,3})\.?\s+([A-Z][^.!?]*)\.?/), words.count <= 8 || !line.hasSuffix(".") {
            return min(m.1.split(separator: ".").count, 3)
        }
        guard let last = line.last, !".,;".contains(last) else { return nil }
        if line.wholeMatch(of: /[IVX]{1,5}\.\s+[A-Z][A-Za-z ,\-]+/) != nil { return 1 }
        let stripped = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .:"))
        if knownHeadings.contains(stripped) { return 1 }
        if line == line.uppercased(), line.rangeOfCharacter(from: .letters) != nil, words.count <= 7, line.count >= 4 {
            return 1
        }
        return nil
    }
}

/// Word, RTF, HTML, ODT. Headings are guessed from font size and weight.
enum RichTextImporter {
    static func load(_ url: URL) throws -> LoadedDocument {
        let attr: NSAttributedString
        do {
            attr = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        } catch {
            throw LoadError.unreadable
        }
        let ns = attr.string as NSString
        let full = NSRange(location: 0, length: attr.length)

        var sizeCounts: [CGFloat: Int] = [:]
        attr.enumerateAttribute(.font, in: full) { value, range, _ in
            if let font = value as? NSFont { sizeCounts[font.pointSize.rounded(), default: 0] += range.length }
        }
        let body = sizeCounts.max { $0.value < $1.value }?.key ?? 12

        var blocks: [Block] = []
        var nextGroup = 0

        // Word and HTML tables arrive as paragraphs tagged with their table, row and column.
        var tableID: ObjectIdentifier?
        var tableCells: [Int: [Int: String]] = [:]
        func flushTable() {
            defer { tableID = nil; tableCells = [:] }
            guard !tableCells.isEmpty else { return }
            let columns = (tableCells.values.flatMap(\.keys).max() ?? 0) + 1
            let rows = tableCells.keys.sorted().map { r in
                (0..<columns).map { c in AttributedString(tableCells[r]?[c] ?? "") }
            }
            let hasHeader = rows.count > 1
            blocks.append(.table(TableData(header: hasHeader ? rows[0] : [], rows: Array(rows.dropFirst(hasHeader ? 1 : 0)))))
        }

        ns.enumerateSubstrings(in: full, options: .byParagraphs) { sub, range, _, _ in
            guard let sub else { return }
            var text = sub.trimmingCharacters(in: .whitespaces)
            let style = attr.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle

            if let cell = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).last {
                let id = ObjectIdentifier(cell.table)
                if tableID != id {
                    flushTable()
                    tableID = id
                }
                let existing = tableCells[cell.startingRow]?[cell.startingColumn] ?? ""
                tableCells[cell.startingRow, default: [:]][cell.startingColumn] = existing.isEmpty ? text : existing + " " + text
                return
            }
            flushTable()
            guard !text.isEmpty else { return }

            var maxSize: CGFloat = 0
            var allBold = true
            attr.enumerateAttribute(.font, in: range) { value, _, _ in
                guard let font = value as? NSFont else { allBold = false; return }
                maxSize = max(maxSize, font.pointSize)
                if !font.fontDescriptor.symbolicTraits.contains(.bold) { allBold = false }
            }
            let short = text.count < 120 && !text.hasSuffix(".")

            if short && maxSize >= body * 1.15 {
                let level = maxSize >= body * 1.6 ? 1 : (maxSize >= body * 1.3 ? 2 : 3)
                blocks.append(Block(kind: .heading(level), text: AttributedString(text)))
            } else if short && allBold && text.count < 80 {
                blocks.append(Block(kind: .heading(3), text: AttributedString(text)))
            } else if (style?.textLists.isEmpty == false) || text.firstMatch(of: /^\s*[•◦▪●–]\s+/) != nil {
                let lists = style?.textLists ?? []
                text = text.replacing(/^\s*([•◦▪●\-–]|\d+[.)])\s*/, with: "")
                let group: Int
                if let last = blocks.last, last.kind.isListItem, let g = last.listGroup {
                    group = g
                } else {
                    group = nextGroup
                    nextGroup += 1
                }
                blocks.append(Block(kind: .listItem(marker: "•", level: max(0, lists.count - 1)), text: AttributedString(text), listGroup: group))
            } else {
                blocks.append(Block(kind: .paragraph, text: AttributedString(text)))
            }
        }
        flushTable()

        let title = blocks.first { $0.kind.isHeading }.map { String($0.text.characters) }
            ?? url.deletingPathExtension().lastPathComponent
        return LoadedDocument(title: title, blocks: blocks)
    }
}
