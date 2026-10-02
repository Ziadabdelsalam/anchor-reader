import Foundation

enum DebugDump {
    static func run(path: String, size: ChunkSize) {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        do {
            let doc: LoadedDocument
            if DocumentLoader.richExtensions.contains(ext) {
                doc = try RichTextImporter.load(url)
            } else if ext == "pdf" {
                doc = try PDFImporter.load(url)
            } else {
                doc = try MarkdownImporter.load(url)
            }
            let out = Chunker.run(doc.blocks, size: size)
            print("TITLE: \(doc.title)")
            print("BLOCKS: \(doc.blocks.count)  CHUNKS: \(out.chunks.count)  WORDS: \(out.totalWords)  SECTIONS: \(out.sections.count)")
            for s in out.sections { print("  \(String(repeating: "  ", count: s.level - 1))§ \(s.title)  → chunk \(s.chunkIndex)") }
            print("---")
            for c in out.chunks {
                let tag = c.isHeading ? "H" : (c.startsParagraph ? "¶" : "·")
                for seg in c.segments {
                    let kind: String
                    switch seg.kind {
                    case .heading(let l): kind = "h\(l)"
                    case .paragraph: kind = "p"
                    case .quote: kind = "quote"
                    case .listItem(let m, let l): kind = "li[\(m)]\(l)"
                    case .code: kind = "code"
                    case .table: kind = "table"
                    }
                    if let table = seg.table {
                        print("\(c.id) \(tag) table \(table.columnCount) cols, rows \(table.firstRow + 1)-\(table.firstRow + table.rows.count) of \(table.totalRows), align \(table.alignments)")
                        let fmt: ([AttributedString]) -> String = { $0.map { String($0.characters) }.joined(separator: " ‖ ") }
                        if !table.header.isEmpty { print("      H: \(fmt(table.header))") }
                        for row in table.rows { print("      R: \(fmt(row).prefix(150))") }
                        continue
                    }
                    let text = seg.plain.replacingOccurrences(of: "\n", with: "⏎")
                    print("\(c.id) \(tag) \(kind) (\(seg.wordCount)w): \(text.prefix(140))")
                }
            }
        } catch {
            print("ERROR: \(error.localizedDescription)")
        }
    }
}
