import AppKit
import SwiftUI

/// Column widths for a table, measured from its actual text in the reader's font.
/// Tables are never cut off and never need sideways scrolling: cells wrap, the table can
/// widen past the text column, and tables too wide to read side by side become cards.
struct TableLayout {
    let widths: [CGFloat]
    let useCards: Bool
    let cellPadding: CGFloat
    /// Width of the label column inside a card.
    let labelWidth: CGFloat

    var gridWidth: CGFloat { widths.reduce(0, +) + CGFloat(max(widths.count - 1, 0)) }

    /// Layouts are cached per table and style, so scrolling never re-measures text.
    private static var cache: [String: TableLayout] = [:]

    static func compute(_ table: TableData, style: TextStyle, available: CGFloat) -> TableLayout {
        let key = "\(table.id)|\(style.font.id)|\(style.tableSize)|\(style.letter)|\(style.word)|\(Int(available))|\(Int(style.columnWidth))"
        if let cached = cache[key] { return cached }
        if cache.count > 400 { cache.removeAll() }
        let layout = measure(table, style: style, available: available)
        cache[key] = layout
        return layout
    }

    private static func measure(_ table: TableData, style: TextStyle, available: CGFloat) -> TableLayout {
        let columns = table.columnCount
        let padding = (style.tableSize * 0.55).rounded()
        guard columns > 0 else { return TableLayout(widths: [], useCards: false, cellPadding: padding, labelWidth: 0) }

        let regular = style.font.nsFont(size: style.tableSize)
        let bold = style.font.nsFont(size: style.tableSize, bold: true)
        func measure(_ text: String, _ font: NSFont) -> CGFloat {
            let base = (text as NSString).size(withAttributes: [.font: font]).width
            let spaces = CGFloat(text.reduce(0) { $1 == " " ? $0 + 1 : $0 })
            // Small safety margin so measured and drawn widths never disagree by a hair.
            return ceil(base * 1.04 + CGFloat(text.count) * style.letter + spaces * style.word) + 2
        }

        var natural = Array(repeating: CGFloat(0), count: columns)
        var minimum = natural
        // A single very long cell wraps instead of stretching its column across the screen.
        let cap = style.tableSize * 17
        for c in 0..<columns {
            var cells: [(String, NSFont)] = table.measureRows.map { (String($0[c].characters), regular) }
            if !table.header.isEmpty { cells.append((String(table.header[c].characters), bold)) }
            for (text, font) in cells {
                natural[c] = max(natural[c], measure(text, font))
                for word in text.split(whereSeparator: { $0.isWhitespace }) {
                    minimum[c] = max(minimum[c], measure(String(word), font))
                }
            }
            natural[c] = min(natural[c], max(cap, minimum[c])) + padding * 2
            minimum[c] += padding * 2
        }

        let room = available - CGFloat(columns - 1)
        if natural.reduce(0, +) <= room {
            return TableLayout(widths: natural, useCards: false, cellPadding: padding, labelWidth: 0)
        }

        let minimumTotal = minimum.reduce(0, +)
        if minimumTotal > room || room / CGFloat(columns) < style.tableSize * 6.5 {
            // Too many columns to read side by side: one card per row instead.
            let longestLabel = table.header.map { measure(String($0.characters), bold) }.max() ?? 0
            let cardWidth = min(available, style.columnWidth)
            return TableLayout(widths: [], useCards: true, cellPadding: padding, labelWidth: min(longestLabel, cardWidth * 0.36))
        }

        // Start every column at its longest word, then share the remaining room
        // in proportion to how much more each column would like.
        let extra = room - minimumTotal
        let wants = zip(natural, minimum).map { $0 - $1 }
        let wantTotal = wants.reduce(0, +)
        let widths = minimum.indices.map { floor(minimum[$0] + (wantTotal > 0 ? extra * wants[$0] / wantTotal : 0)) }
        return TableLayout(widths: widths, useCards: false, cellPadding: padding, labelWidth: 0)
    }
}

struct TableView: View {
    let table: TableData
    let layout: TableLayout
    let style: TextStyle
    /// Row being read aloud, if any.
    let highlightRow: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: style.tableSize * 0.45) {
            if let caption {
                Text(caption)
                    .font(.system(size: max(15, style.tableSize * 0.72), weight: .medium))
                    .foregroundStyle(style.theme.secondary)
            }
            if layout.useCards { cards } else { grid }
        }
    }

    private var caption: String? {
        var parts: [String] = []
        if table.isSplit {
            parts.append("Rows \(table.firstRow + 1)–\(table.firstRow + table.rows.count) of \(table.totalRows)")
        }
        if layout.useCards {
            parts.append("\(table.columnCount) columns, shown as cards so nothing is cut off")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var border: Color { style.theme.secondary.opacity(0.35) }

    // MARK: Grid

    private var grid: some View {
        VStack(spacing: 0) {
            if !table.header.isEmpty {
                row(table.header, isHeader: true, index: -1)
                Rectangle().fill(border).frame(height: 1.5)
            }
            ForEach(table.rows.indices, id: \.self) { r in
                row(table.rows[r], isHeader: false, index: r)
                if r < table.rows.count - 1 {
                    Rectangle().fill(border.opacity(0.6)).frame(height: 1)
                }
            }
        }
        .frame(width: layout.gridWidth)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(border, lineWidth: 1))
    }

    private func row(_ cells: [AttributedString], isHeader: Bool, index: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(cells.indices, id: \.self) { c in
                Text(style.spaced(cells[c]))
                    .font(style.tableFont)
                    .fontWeight(isHeader ? .semibold : .regular)
                    .foregroundStyle(style.theme.text)
                    .lineSpacing(style.lineExtra * 0.45)
                    .multilineTextAlignment(textAlignment(c))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: max(0, layout.widths[c] - layout.cellPadding * 2), alignment: frameAlignment(c))
                    .padding(.horizontal, layout.cellPadding)
                    .padding(.vertical, layout.cellPadding * 0.7)
                    .frame(maxHeight: .infinity, alignment: .top)
                if c < cells.count - 1 {
                    Rectangle().fill(border.opacity(0.6)).frame(width: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(rowBackground(isHeader: isHeader, index: index))
    }

    private func rowBackground(isHeader: Bool, index: Int) -> Color {
        if index >= 0 && index == highlightRow { return style.theme.speech.opacity(0.8) }
        if isHeader { return style.theme.codeBackground }
        return index % 2 == 1 ? style.theme.codeBackground.opacity(0.45) : .clear
    }

    private func textAlignment(_ column: Int) -> TextAlignment {
        switch table.alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func frameAlignment(_ column: Int) -> Alignment {
        switch table.alignments[column] {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }

    // MARK: Cards

    private var cards: some View {
        VStack(alignment: .leading, spacing: style.tableSize * 0.6) {
            ForEach(table.rows.indices, id: \.self) { r in
                card(r)
            }
        }
    }

    private func card(_ r: Int) -> some View {
        let row = table.rows[r]
        let hasHeader = !table.header.isEmpty
        return VStack(alignment: .leading, spacing: style.tableSize * 0.4) {
            if let first = row.first {
                Text(style.spaced(first))
                    .font(style.tableFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(style.theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(row.indices.dropFirst()), id: \.self) { c in
                if !row[c].characters.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: style.tableSize * 0.6) {
                        if hasHeader {
                            Text(style.spaced(table.header[c]))
                                .font(style.tableFont)
                                .fontWeight(.medium)
                                .foregroundStyle(style.theme.secondary)
                                .frame(width: layout.labelWidth, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(style.spaced(row[c]))
                            .font(style.tableFont)
                            .foregroundStyle(style.theme.text)
                            .lineSpacing(style.lineExtra * 0.45)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(layout.cellPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(r == highlightRow ? style.theme.speech.opacity(0.8) : style.theme.codeBackground.opacity(0.7))
        )
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(border, lineWidth: 1))
    }
}
