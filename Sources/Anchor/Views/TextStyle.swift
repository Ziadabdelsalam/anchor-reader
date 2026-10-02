import SwiftUI

/// Typography resolved from settings: font, size, spacing, column width, colors.
struct TextStyle {
    typealias Kern = AttributeScopes.SwiftUIAttributes.KerningAttribute
    typealias Background = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

    let font: FontOption
    let size: CGFloat
    let letter: CGFloat
    let word: CGFloat
    let lineExtra: CGFloat
    let theme: Theme
    let columnWidth: CGFloat

    init(_ s: ReaderSettings) {
        font = FontOption.option(for: s.fontID)
        size = CGFloat(s.fontSize)
        letter = CGFloat(s.letterSpacing)
        word = CGFloat(s.wordSpacing)
        lineExtra = max(0, CGFloat(s.lineHeight - 1.2) * CGFloat(s.fontSize))
        theme = s.theme.palette
        let chars = CGFloat(s.lineLength)
        columnWidth = chars * (size * font.widthFactor + letter) + chars / 6 * word + size * 1.4
    }

    var body: Font { font.font(size: size) }

    func heading(_ level: Int) -> Font {
        let scale: [CGFloat] = [1.55, 1.32, 1.16, 1.06]
        return font.font(size: size * scale[min(max(level, 1), 4) - 1])
    }

    /// Code and tables never shrink below a comfortable size.
    var codeSize: CGFloat { max(16, size * 0.82) }

    /// Table text stays close to body size and never below the app's 18 pt minimum.
    var tableSize: CGFloat { max(CGFloat(ReaderSettings.minFontSize), size * 0.88) }
    var tableFont: Font { font.font(size: tableSize) }

    /// Applies letter and word spacing to any attributed text.
    /// Built piece by piece so no AttributedString index is used after a mutation.
    func spaced(_ text: AttributedString) -> AttributedString {
        var out = AttributedString()
        for run in text.runs {
            let runText = String(text[run.range].characters)
            let attributes = run.attributes
            var buffer = ""
            var bufferIsSpace: Bool?
            func flush() {
                guard !buffer.isEmpty else { return }
                var piece = AttributedString(buffer, attributes: attributes)
                piece[Kern.self] = bufferIsSpace == true ? letter + word : letter
                out.append(piece)
                buffer = ""
            }
            for character in runText {
                let isSpace = character == " "
                if bufferIsSpace != isSpace {
                    flush()
                    bufferIsSpace = isSpace
                }
                buffer.append(character)
            }
            flush()
        }
        return out
    }

    /// Spacing plus the read-aloud word highlight for a segment.
    func styled(_ segment: Segment, highlight: NSRange?) -> AttributedString {
        var out = spaced(segment.text)

        if let highlight {
            let plain = segment.plain
            if let range = Range(highlight, in: plain) {
                let start = plain.distance(from: plain.startIndex, to: range.lowerBound)
                let end = plain.distance(from: plain.startIndex, to: range.upperBound)
                let characters = out.characters
                if start < end, end <= characters.count {
                    let s = characters.index(characters.startIndex, offsetBy: start)
                    let e = characters.index(characters.startIndex, offsetBy: end)
                    out[s..<e][Background.self] = theme.speech
                }
            }
        }
        return out
    }
}
