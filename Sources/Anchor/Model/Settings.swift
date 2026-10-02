import AppKit
import SwiftUI

nonisolated enum ChunkSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case sentence, small, medium, paragraph

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sentence: "One sentence"
        case .small: "Bite-size (~2 sentences)"
        case .medium: "Short (~4 sentences)"
        case .paragraph: "Whole paragraph"
        }
    }

    var wordLimit: Int {
        switch self {
        case .sentence: 0
        case .small: 35
        case .medium: 70
        case .paragraph: .max
        }
    }
}

nonisolated enum CheckpointMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, sections, frequent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .sections: "At the end of each section"
        case .frequent: "Often (every few paragraphs)"
        }
    }
}

nonisolated enum ThemeID: String, Codable, CaseIterable, Identifiable, Sendable {
    case paper, white, sepia, gray, night, blue, green, rose

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paper: "Paper"
        case .white: "White"
        case .sepia: "Sepia"
        case .gray: "Soft gray"
        case .night: "Night"
        case .blue: "Blue tint"
        case .green: "Green tint"
        case .rose: "Rose tint"
        }
    }
}

/// Everything the reader can tune. Defaults lean large and roomy on purpose:
/// bigger text and extra letter spacing helped readers in the studies this app is based on.
nonisolated struct ReaderSettings: Codable, Equatable, Sendable {
    static let minFontSize: Double = 18
    static let maxFontSize: Double = 56
    static let defaultFontSize: Double = 24

    var fontID = "system"
    var fontSize: Double = ReaderSettings.defaultFontSize
    var letterSpacing: Double = 0.6
    var wordSpacing: Double = 3
    var lineHeight: Double = 1.7
    var lineLength: Double = 60
    var interfaceSize: Double = 16
    var theme: ThemeID = .paper
    var dimLevel: Double = 0.2
    var spotlight = true
    var chunkSize: ChunkSize = .small
    var sprintMinutes = 5
    var breakMinutes = 1
    var checkpoints: CheckpointMode = .sections
    var nudges = true
    var sounds = true
    var speechRate: Double = 0.48
    var voiceID: String?
    var autoAdvance = true
    var comfortSetupDone = false
    var fontFinderResults: [String: Double] = [:]

    init() {}

    // Tolerant decoding so adding a setting never wipes the old ones.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReaderSettings()
        fontID = (try? c.decode(String.self, forKey: .fontID)) ?? d.fontID
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? d.fontSize
        letterSpacing = (try? c.decode(Double.self, forKey: .letterSpacing)) ?? d.letterSpacing
        wordSpacing = (try? c.decode(Double.self, forKey: .wordSpacing)) ?? d.wordSpacing
        lineHeight = (try? c.decode(Double.self, forKey: .lineHeight)) ?? d.lineHeight
        lineLength = (try? c.decode(Double.self, forKey: .lineLength)) ?? d.lineLength
        interfaceSize = (try? c.decode(Double.self, forKey: .interfaceSize)) ?? d.interfaceSize
        theme = (try? c.decode(ThemeID.self, forKey: .theme)) ?? d.theme
        dimLevel = (try? c.decode(Double.self, forKey: .dimLevel)) ?? d.dimLevel
        spotlight = (try? c.decode(Bool.self, forKey: .spotlight)) ?? d.spotlight
        chunkSize = (try? c.decode(ChunkSize.self, forKey: .chunkSize)) ?? d.chunkSize
        sprintMinutes = (try? c.decode(Int.self, forKey: .sprintMinutes)) ?? d.sprintMinutes
        breakMinutes = (try? c.decode(Int.self, forKey: .breakMinutes)) ?? d.breakMinutes
        checkpoints = (try? c.decode(CheckpointMode.self, forKey: .checkpoints)) ?? d.checkpoints
        nudges = (try? c.decode(Bool.self, forKey: .nudges)) ?? d.nudges
        sounds = (try? c.decode(Bool.self, forKey: .sounds)) ?? d.sounds
        speechRate = (try? c.decode(Double.self, forKey: .speechRate)) ?? d.speechRate
        voiceID = try? c.decode(String.self, forKey: .voiceID)
        autoAdvance = (try? c.decode(Bool.self, forKey: .autoAdvance)) ?? d.autoAdvance
        comfortSetupDone = (try? c.decode(Bool.self, forKey: .comfortSetupDone)) ?? d.comfortSetupDone
        fontFinderResults = (try? c.decode([String: Double].self, forKey: .fontFinderResults)) ?? d.fontFinderResults
        fontSize = min(max(fontSize, Self.minFontSize), Self.maxFontSize)
    }
}

@Observable
final class SettingsStore {
    var s: ReaderSettings {
        didSet { if s != oldValue { save() } }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "readerSettings"),
           let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data) {
            s = decoded
        } else {
            s = ReaderSettings()
        }
    }

    var font: FontOption { FontOption.option(for: s.fontID) }
    var theme: Theme { s.theme.palette }
    var ui: CGFloat { CGFloat(s.interfaceSize) }

    func biggerText() { s.fontSize = min(s.fontSize + 2, ReaderSettings.maxFontSize) }
    func smallerText() { s.fontSize = max(s.fontSize - 2, ReaderSettings.minFontSize) }

    private func save() {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: "readerSettings")
        }
    }
}

// MARK: - Themes

struct Theme {
    let background: Color
    let text: Color
    let secondary: Color
    let highlight: Color
    let accent: Color
    let speech: Color
    let codeBackground: Color
    let isDark: Bool
}

extension ThemeID {
    var palette: Theme {
        switch self {
        case .paper:
            Theme(background: Color(hex: 0xFBF8F1), text: Color(hex: 0x1E1C19), secondary: Color(hex: 0x6B655C),
                  highlight: Color(hex: 0xF1E8D4), accent: Color(hex: 0xC8742A), speech: Color(hex: 0xFFDF85),
                  codeBackground: Color(hex: 0xF0EBE0), isDark: false)
        case .white:
            Theme(background: .white, text: Color(hex: 0x111111), secondary: Color(hex: 0x5F6368),
                  highlight: Color(hex: 0xEEF2F7), accent: Color(hex: 0x2F6FEB), speech: Color(hex: 0xFFE58F),
                  codeBackground: Color(hex: 0xF3F4F6), isDark: false)
        case .sepia:
            Theme(background: Color(hex: 0xF4EAD5), text: Color(hex: 0x3A2E22), secondary: Color(hex: 0x7A6650),
                  highlight: Color(hex: 0xE9DBBC), accent: Color(hex: 0x9B5B2A), speech: Color(hex: 0xF6D27A),
                  codeBackground: Color(hex: 0xEADFC6), isDark: false)
        case .gray:
            Theme(background: Color(hex: 0xE8E9EB), text: Color(hex: 0x1F2328), secondary: Color(hex: 0x5C636B),
                  highlight: Color(hex: 0xD9DCE1), accent: Color(hex: 0x3D6FB6), speech: Color(hex: 0xFFE08A),
                  codeBackground: Color(hex: 0xDDDFE3), isDark: false)
        case .night:
            Theme(background: Color(hex: 0x17181A), text: Color(hex: 0xE6E1D6), secondary: Color(hex: 0x9A958C),
                  highlight: Color(hex: 0x25272B), accent: Color(hex: 0xE3A857), speech: Color(hex: 0x6B5520),
                  codeBackground: Color(hex: 0x222428), isDark: true)
        case .blue:
            Theme(background: Color(hex: 0xE6F0FA), text: Color(hex: 0x14202E), secondary: Color(hex: 0x52637A),
                  highlight: Color(hex: 0xD3E3F4), accent: Color(hex: 0x2F6FB6), speech: Color(hex: 0xFFE38F),
                  codeBackground: Color(hex: 0xD9E6F3), isDark: false)
        case .green:
            Theme(background: Color(hex: 0xE8F3E5), text: Color(hex: 0x17241A), secondary: Color(hex: 0x56685A),
                  highlight: Color(hex: 0xD5E9D0), accent: Color(hex: 0x3F8A4E), speech: Color(hex: 0xFFE38F),
                  codeBackground: Color(hex: 0xDCEBD8), isDark: false)
        case .rose:
            Theme(background: Color(hex: 0xF9EAEC), text: Color(hex: 0x2A171B), secondary: Color(hex: 0x76585E),
                  highlight: Color(hex: 0xF0D6DB), accent: Color(hex: 0xB5506A), speech: Color(hex: 0xFFE08A),
                  codeBackground: Color(hex: 0xF1DDE0), isDark: false)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Fonts

struct FontOption: Identifiable, Hashable {
    let id: String
    let name: String
    /// nil means a built-in system design (SF Pro / New York / SF Rounded).
    let family: String?
    let design: Font.Design?
    /// Rough average glyph width as a fraction of the point size, used to size the text column.
    var widthFactor: CGFloat = 0.5

    func font(size: CGFloat) -> Font {
        if let design { return .system(size: size, design: design) }
        return .custom(family ?? "", fixedSize: size)
    }

    /// The AppKit equivalent, used to measure text (e.g. table column widths).
    func nsFont(size: CGFloat, bold: Bool = false) -> NSFont {
        let weight: NSFont.Weight = bold ? .semibold : .regular
        if let design {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let systemDesign: NSFontDescriptor.SystemDesign = switch design {
            case .serif: .serif
            case .rounded: .rounded
            case .monospaced: .monospaced
            default: .default
            }
            if let descriptor = base.fontDescriptor.withDesign(systemDesign), let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
            return base
        }
        if let family, let font = NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: 5, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static let all: [FontOption] = [
        FontOption(id: "system", name: "SF Pro", family: nil, design: .default, widthFactor: 0.5),
        FontOption(id: "system-serif", name: "New York", family: nil, design: .serif, widthFactor: 0.5),
        FontOption(id: "system-rounded", name: "SF Pro Rounded", family: nil, design: .rounded, widthFactor: 0.51),
        FontOption(id: "atkinson-next", name: "Atkinson Hyperlegible Next", family: "Atkinson Hyperlegible Next", design: nil, widthFactor: 0.52),
        FontOption(id: "atkinson", name: "Atkinson Hyperlegible", family: "Atkinson Hyperlegible", design: nil, widthFactor: 0.52),
        FontOption(id: "lexend", name: "Lexend", family: "Lexend", design: nil, widthFactor: 0.55),
        FontOption(id: "georgia", name: "Georgia", family: "Georgia", design: nil, widthFactor: 0.5),
        FontOption(id: "charter", name: "Charter", family: "Charter", design: nil, widthFactor: 0.5),
        FontOption(id: "iowan", name: "Iowan Old Style", family: "Iowan Old Style", design: nil, widthFactor: 0.5),
        FontOption(id: "palatino", name: "Palatino", family: "Palatino", design: nil, widthFactor: 0.48),
        FontOption(id: "avenir", name: "Avenir Next", family: "Avenir Next", design: nil, widthFactor: 0.5),
        FontOption(id: "helvetica", name: "Helvetica Neue", family: "Helvetica Neue", design: nil, widthFactor: 0.5),
        FontOption(id: "verdana", name: "Verdana", family: "Verdana", design: nil, widthFactor: 0.58),
        FontOption(id: "optima", name: "Optima", family: "Optima", design: nil, widthFactor: 0.5),
        FontOption(id: "trebuchet", name: "Trebuchet MS", family: "Trebuchet MS", design: nil, widthFactor: 0.5),
        FontOption(id: "comic", name: "Comic Sans MS", family: "Comic Sans MS", design: nil, widthFactor: 0.55),
        FontOption(id: "opendyslexic", name: "OpenDyslexic", family: "OpenDyslexic", design: nil, widthFactor: 0.62),
    ]

    static var available: [FontOption] {
        let families = Set(NSFontManager.shared.availableFontFamilies)
        return all.filter { option in
            guard let family = option.family else { return true }
            return families.contains(family)
        }
    }

    static func option(for id: String) -> FontOption {
        all.first { $0.id == id } ?? all[0]
    }

    /// The fonts the Font Finder compares: a spread of styles that ship with macOS,
    /// plus any accessibility fonts the user has installed.
    static var finderCandidates: [FontOption] {
        let preferred = ["atkinson-next", "atkinson", "lexend", "system", "system-serif", "georgia", "avenir", "verdana", "charter"]
        let available = Dictionary(uniqueKeysWithValues: Self.available.map { ($0.id, $0) })
        return Array(preferred.compactMap { available[$0] }.prefix(6))
    }
}
