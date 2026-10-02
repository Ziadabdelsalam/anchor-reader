import Foundation
import NaturalLanguage

/// Cuts parsed blocks into small reading chunks. Long paragraphs are split on
/// sentence boundaries so you only ever face a few lines at a time.
nonisolated enum Chunker {
    struct Output: Sendable {
        var chunks: [Chunk]
        var sections: [DocSection]
        var totalWords: Int
    }

    static func run(_ blocks: [Block], size: ChunkSize) -> Output {
        var chunks: [Chunk] = []
        var sections: [DocSection] = []
        var segmentID = 0
        var words = 0
        var currentSection: Int?

        var pendingList: [Segment] = []
        var pendingWords = 0
        var pendingGroup: Int?
        var listChunkCount = 0

        let listLimit = size == .paragraph ? 120 : size.wordLimit

        func makeSegment(_ kind: SegmentKind, _ text: AttributedString) -> Segment {
            defer { segmentID += 1 }
            return Segment(id: segmentID, kind: kind, text: text, wordCount: countWords(String(text.characters)))
        }

        func emit(_ segments: [Segment], startsParagraph: Bool, isHeading: Bool = false) {
            let count = segments.reduce(0) { $0 + $1.wordCount }
            chunks.append(Chunk(
                id: chunks.count,
                segments: segments,
                sectionIndex: currentSection,
                wordCount: count,
                wordOffset: words,
                startsParagraph: startsParagraph,
                isHeading: isHeading
            ))
            words += count
        }

        func flushList() {
            guard !pendingList.isEmpty else { return }
            emit(pendingList, startsParagraph: listChunkCount == 0)
            listChunkCount += 1
            pendingList.removeAll()
            pendingWords = 0
        }

        func endList() {
            flushList()
            pendingGroup = nil
            listChunkCount = 0
        }

        for block in blocks {
            switch block.kind {
            case .heading(let level):
                endList()
                let segment = makeSegment(block.kind, block.text)
                sections.append(DocSection(id: sections.count, title: segment.plain, level: level, chunkIndex: chunks.count))
                currentSection = sections.count - 1
                emit([segment], startsParagraph: true, isHeading: true)

            case .paragraph, .quote:
                endList()
                for (k, piece) in split(block.text, size: size).enumerated() {
                    emit([makeSegment(block.kind, piece)], startsParagraph: k == 0)
                }

            case .listItem(let marker, let level):
                if block.listGroup != pendingGroup {
                    endList()
                    pendingGroup = block.listGroup
                }
                let pieces = split(block.text, size: size)
                if pieces.count > 1 {
                    flushList()
                    for (k, piece) in pieces.enumerated() {
                        let kind = SegmentKind.listItem(marker: k == 0 ? marker : "", level: level)
                        emit([makeSegment(kind, piece)], startsParagraph: listChunkCount == 0 && k == 0)
                        listChunkCount += 1
                    }
                } else {
                    let segment = makeSegment(block.kind, block.text)
                    if !pendingList.isEmpty && pendingWords + segment.wordCount > max(listLimit, 0) {
                        flushList()
                    }
                    pendingList.append(segment)
                    pendingWords += segment.wordCount
                }

            case .table:
                endList()
                guard let table = block.table else {
                    emit([makeSegment(block.kind, block.text)], startsParagraph: true)
                    break
                }
                // Long tables become several bites of a few rows each; every part keeps the header.
                for (k, range) in tableRowGroups(table, size: size).enumerated() {
                    let part = table.slice(range)
                    var segment = makeSegment(.table, AttributedString(part.plainText))
                    segment.table = part
                    emit([segment], startsParagraph: k == 0)
                }

            case .code:
                endList()
                emit([makeSegment(block.kind, block.text)], startsParagraph: true)
            }
        }
        endList()
        return Output(chunks: chunks, sections: sections, totalWords: words)
    }

    static func tableRowGroups(_ table: TableData, size: ChunkSize) -> [Range<Int>] {
        let count = table.rows.count
        guard count > 0 else { return [0..<0] }
        var (maxRows, wordBudget): (Int, Int) = switch size {
        case .sentence: (3, 45)
        case .small: (5, 90)
        case .medium: (8, 160)
        case .paragraph: (14, 320)
        }
        // Wide tables usually show as one card per row, with every header repeated as a label,
        // so each row is much taller. Keep those bites to a card or two.
        let wide = table.columnCount >= 6
        if wide { maxRows = [ChunkSize.sentence: 1, .small: 2, .medium: 3, .paragraph: 5][size] ?? 2 }
        let headerWords = table.columnCount >= 5 ? table.header.reduce(0) { $0 + countWords(String($1.characters)) } : 0
        let words = table.rows.map { row in headerWords + row.reduce(0) { $0 + countWords(String($1.characters)) } }
        var groups: [Range<Int>] = []
        var start = 0
        var rowsInGroup = 0
        var wordsInGroup = 0
        for r in 0..<count {
            if rowsInGroup > 0 && (rowsInGroup >= maxRows || wordsInGroup + words[r] > wordBudget) {
                groups.append(start..<r)
                start = r
                rowsInGroup = 0
                wordsInGroup = 0
            }
            rowsInGroup += 1
            wordsInGroup += words[r]
        }
        groups.append(start..<count)
        // A lone last row reads better attached to the part before it.
        if groups.count > 1, let last = groups.last, last.count == 1, !wide,
           groups[groups.count - 2].count < maxRows + 2,
           words[groups[groups.count - 2]].reduce(0, +) + words[last.lowerBound] <= wordBudget * 5 / 4 {
            let previous = groups[groups.count - 2]
            groups.removeLast(2)
            groups.append(previous.lowerBound..<last.upperBound)
        }
        return groups
    }

    static func split(_ text: AttributedString, size: ChunkSize) -> [AttributedString] {
        guard size != .paragraph else { return [text] }
        let chars = Array(text.characters)
        let limit = size == .sentence ? 30 : size.wordLimit
        let units = sentenceOffsets(String(chars)).flatMap { breakLongSentence($0, chars: chars, limit: limit) }
        guard units.count > 1 else { return [text] }

        var groups: [(start: Int, end: Int, words: Int)] = []
        if size == .sentence {
            groups = units.map { ($0.0, $0.1, words(chars, $0)) }
        } else {
            for unit in units {
                let wc = words(chars, unit)
                if let last = groups.last, last.words + wc <= limit {
                    groups[groups.count - 1] = (last.start, unit.1, last.words + wc)
                } else {
                    groups.append((unit.0, unit.1, wc))
                }
            }
        }

        // Don't leave a tiny orphan at the end of a paragraph.
        if groups.count > 1, let last = groups.last, last.words < 8 {
            let previous = groups[groups.count - 2]
            groups.removeLast(2)
            groups.append((previous.start, last.end, previous.words + last.words))
        }

        let characters = text.characters
        return groups.map { group in
            let s = characters.index(characters.startIndex, offsetBy: group.start)
            let e = characters.index(characters.startIndex, offsetBy: group.end)
            return AttributedString(text[s..<e])
        }
    }

    private static func words(_ chars: [Character], _ unit: (Int, Int)) -> Int {
        countWords(String(chars[unit.0..<unit.1]))
    }

    /// Sentence boundaries as character offsets, with surrounding whitespace trimmed.
    static func sentenceOffsets(_ plain: String) -> [(Int, Int)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = plain
        var offsets: [(Int, Int)] = []
        tokenizer.enumerateTokens(in: plain.startIndex..<plain.endIndex) { range, _ in
            var lower = range.lowerBound
            var upper = range.upperBound
            while lower < upper, plain[lower].isWhitespace { lower = plain.index(after: lower) }
            while upper > lower, plain[plain.index(before: upper)].isWhitespace { upper = plain.index(before: upper) }
            if lower < upper {
                offsets.append((plain.distance(from: plain.startIndex, to: lower), plain.distance(from: plain.startIndex, to: upper)))
            }
            return true
        }
        return offsets
    }

    /// Academic and legal sentences can run past 100 words. Break those at clause
    /// boundaries (semicolons, colons, dashes, then commas) so no bite becomes a wall.
    static func breakLongSentence(_ unit: (Int, Int), chars: [Character], limit: Int) -> [(Int, Int)] {
        let maxWords = max(limit * 3 / 2, 40)
        guard words(chars, unit) > maxWords else { return [unit] }

        func cut(_ range: (Int, Int), after separators: Set<Character>) -> [(Int, Int)] {
            var pieces: [(Int, Int)] = []
            var start = range.0
            var p = range.0
            while p < range.1 - 1 {
                if separators.contains(chars[p]), chars[p + 1] == " ", p + 1 > start {
                    pieces.append((start, p + 1))
                    start = p + 1
                }
                p += 1
            }
            pieces.append((start, range.1))
            return pieces.map { trim($0) }.filter { $0.0 < $0.1 }
        }

        func trim(_ r: (Int, Int)) -> (Int, Int) {
            var (s, e) = r
            while s < e, chars[s].isWhitespace { s += 1 }
            while e > s, chars[e - 1].isWhitespace { e -= 1 }
            return (s, e)
        }

        func hardSplit(_ range: (Int, Int)) -> [(Int, Int)] {
            var pieces: [(Int, Int)] = []
            var start = range.0
            var count = 0
            var p = range.0
            while p < range.1 {
                if chars[p] == " " {
                    count += 1
                    if count >= limit {
                        pieces.append(trim((start, p)))
                        start = p
                        count = 0
                    }
                }
                p += 1
            }
            pieces.append(trim((start, range.1)))
            return pieces.filter { $0.0 < $0.1 }
        }

        var pieces = cut(unit, after: [";", ":", "—", "–"])
        pieces = pieces.flatMap { words(chars, $0) > maxWords ? cut($0, after: [","]) : [$0] }

        // Re-join tiny clauses so bites stay a sensible size.
        var merged: [(Int, Int)] = []
        var mergedWords: [Int] = []
        for piece in pieces {
            let wc = words(chars, piece)
            if let last = merged.last, mergedWords[mergedWords.count - 1] + wc <= limit {
                merged[merged.count - 1] = (last.0, piece.1)
                mergedWords[mergedWords.count - 1] += wc
            } else {
                merged.append(piece)
                mergedWords.append(wc)
            }
        }
        return merged.flatMap { words(chars, $0) > maxWords * 3 / 2 ? hardSplit($0) : [$0] }
    }
}
