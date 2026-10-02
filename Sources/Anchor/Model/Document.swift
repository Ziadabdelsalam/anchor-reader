import Foundation

/// What a piece of text is, structurally. Drives how it is drawn and read aloud.
nonisolated enum SegmentKind: Hashable, Sendable {
    case heading(Int)
    case paragraph
    case quote
    case listItem(marker: String, level: Int)
    case code(language: String?)
    case table

    var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }

    var isListItem: Bool {
        if case .listItem = self { return true }
        return false
    }

    var isCode: Bool {
        switch self {
        case .code, .table: return true
        default: return false
        }
    }
}

/// A table, kept as real rows and cells so it can be laid out to fit the window.
nonisolated struct TableData: Sendable {
    enum Align: Sendable { case leading, center, trailing }

    /// Shared by every part of a split table, so all parts use the same column widths.
    let id = UUID()
    /// Empty when the source table has no header row.
    var header: [AttributedString]
    var rows: [[AttributedString]]
    /// All rows of the original table (rows above is just this part), used to size columns.
    var measureRows: [[AttributedString]]
    var alignments: [Align]
    /// When a long table is split across several chunks: index of this part's first row.
    var firstRow = 0
    /// Total body rows in the original table.
    var totalRows = 0

    init(header: [AttributedString], rows: [[AttributedString]], alignments: [Align] = []) {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        // Pad ragged rows so every row has every column; nothing is dropped.
        self.header = header.isEmpty ? [] : header + Array(repeating: AttributedString(), count: columns - header.count)
        self.rows = rows.map { $0 + Array(repeating: AttributedString(), count: columns - $0.count) }
        self.measureRows = self.rows
        self.alignments = (0..<columns).map { $0 < alignments.count ? alignments[$0] : .leading }
        self.totalRows = rows.count
    }

    var columnCount: Int { alignments.count }
    var isSplit: Bool { rows.count < totalRows }

    func slice(_ range: Range<Int>) -> TableData {
        var copy = self
        copy.rows = Array(rows[range])
        copy.firstRow = range.lowerBound
        return copy
    }

    /// Plain-text version, used for word counts and copying.
    var plainText: String {
        ([header] + rows).filter { !$0.isEmpty }
            .map { $0.map { String($0.characters) }.joined(separator: " | ") }
            .joined(separator: "\n")
    }

    /// How a row is read aloud: "Header: value. Header: value."
    func spokenRow(_ index: Int) -> String {
        let row = rows[index]
        let parts = row.indices.compactMap { c -> String? in
            let value = String(row[c].characters).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            let label = c < header.count ? String(header[c].characters).trimmingCharacters(in: .whitespaces) : ""
            return label.isEmpty ? value : "\(label): \(value)"
        }
        return parts.joined(separator: ". ")
    }
}

/// A block as it comes out of a parser, before it is cut into reading chunks.
nonisolated struct Block: Sendable {
    var kind: SegmentKind
    var text: AttributedString
    /// Consecutive list items share a group so they can be read together.
    var listGroup: Int? = nil
    var table: TableData? = nil

    init(kind: SegmentKind, text: AttributedString, listGroup: Int? = nil, table: TableData? = nil) {
        self.kind = kind
        self.text = text
        self.listGroup = listGroup
        self.table = table
    }

    static func table(_ data: TableData) -> Block {
        Block(kind: .table, text: AttributedString(data.plainText), table: data)
    }
}

/// One visual line-group inside a chunk (a paragraph slice, a list item, a heading...).
nonisolated struct Segment: Identifiable, Sendable {
    let id: Int
    var kind: SegmentKind
    var text: AttributedString
    var wordCount: Int
    var table: TableData? = nil

    var plain: String { String(text.characters) }
}

/// The unit the reader moves through with the space bar.
nonisolated struct Chunk: Identifiable, Sendable {
    let id: Int
    var segments: [Segment]
    var sectionIndex: Int?
    var wordCount: Int
    /// Words that come before this chunk in the document. Used to keep your place
    /// even when the chunk size setting changes.
    var wordOffset: Int
    /// True for the first chunk of a paragraph / list / block (gets a bigger gap above).
    var startsParagraph: Bool
    var isHeading: Bool
}

nonisolated struct DocSection: Identifiable, Sendable {
    let id: Int
    var title: String
    var level: Int
    var chunkIndex: Int
}

nonisolated struct LoadedDocument: Sendable {
    var title: String
    var blocks: [Block]
    var language: String?
}

nonisolated enum LoadError: LocalizedError {
    case unreadable
    case locked
    case noText
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file couldn't be read."
        case .locked: "This PDF is password-protected. Unlock it in Preview first."
        case .noText: "No readable text was found. If this is a scanned PDF, run it through OCR (Preview or Adobe can do this) first."
        case .unsupported(let ext): "Anchor can't open .\(ext) files yet. Try Markdown, text, PDF, Word, RTF or HTML."
        }
    }
}

nonisolated func countWords(_ s: String) -> Int {
    s.split(whereSeparator: { $0.isWhitespace }).count
}
