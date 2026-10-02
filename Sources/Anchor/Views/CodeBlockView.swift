import AppKit
import SwiftUI

/// How a code block (or ASCII diagram) is sized. Lines are never wrapped or clipped:
/// the block widens past the text column if it needs to, and if even the full window is
/// too narrow, the font shrinks just enough for the longest line to fit.
struct CodeLayout {
    let fontSize: CGFloat
    /// 1 at full size; below 1 when shrunk to fit.
    let scale: CGFloat
    /// Width of the block including padding.
    let width: CGFloat
    let padding: CGFloat

    var isShrunk: Bool { scale < 0.98 }

    private static var cache: [String: CodeLayout] = [:]

    static func compute(_ text: String, style: TextStyle, available: CGFloat) -> CodeLayout {
        let base = style.codeSize
        let key = "\(text.hashValue)|\(base)|\(Int(available))"
        if let cached = cache[key] { return cached }
        if cache.count > 400 { cache.removeAll() }

        let padding: CGFloat = 16
        let font = NSFont.monospacedSystemFont(ofSize: base, weight: .regular)
        let longest = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // A small margin so the measured and drawn widths can never disagree into clipping.
        let natural = ceil(longest * 1.02) + 2
        let room = max(80, available - padding * 2)
        let scale = min(1, room / max(natural, 1))
        let fontSize = scale < 1 ? floor(base * scale * 10) / 10 : base
        let layout = CodeLayout(
            fontSize: fontSize,
            scale: fontSize / base,
            width: ceil(natural * fontSize / base) + padding * 2,
            padding: padding
        )
        cache[key] = layout
        return layout
    }
}

struct CodeBlockView: View {
    let text: AttributedString
    let layout: CodeLayout
    let style: TextStyle
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if layout.isShrunk {
                HStack(spacing: 10) {
                    Text("Shown at \(Int((layout.scale * 100).rounded()))% so every line fits")
                        .foregroundStyle(style.theme.secondary)
                    Button {
                        app.codeViewer = CodeViewerItem(text: String(text.characters))
                    } label: {
                        Label("View full size", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(style.theme.accent)
                }
                .font(.system(size: max(15, style.tableSize * 0.72), weight: .medium))
            }
            Text(text)
                .font(.system(size: layout.fontSize, design: .monospaced))
                .foregroundStyle(style.theme.text)
                // No extra line spacing: vertical lines in diagrams stay connected.
                .lineSpacing(0)
                .fixedSize()
                .padding(layout.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(style.theme.codeBackground)
                )
        }
    }
}

struct CodeViewerItem: Identifiable {
    let id = UUID()
    let text: String
}

/// A code block or diagram at full size, scrollable in both directions.
struct CodeViewer: View {
    let item: CodeViewerItem
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let theme = app.settings.theme
        let size = max(16, CGFloat(app.settings.s.fontSize) * 0.82)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Full size")
                    .font(.system(size: app.settings.ui * 1.2, weight: .semibold))
                Text("Scroll sideways and up/down to see everything")
                    .font(.system(size: app.settings.ui * 0.9))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                    copied = true
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(16)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Text(item.text)
                    .font(.system(size: size, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .lineSpacing(0)
                    .fixedSize()
                    .textSelection(.enabled)
                    .padding(24)
            }
            .scrollIndicators(.visible)
            .background(theme.codeBackground)
        }
        .frame(width: 900, height: 620)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}
