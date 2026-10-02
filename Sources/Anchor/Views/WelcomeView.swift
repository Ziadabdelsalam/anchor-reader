import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack {
            if let reader = app.reader {
                ReaderScreen(model: reader)
                    .id(ObjectIdentifier(reader))
            } else {
                WelcomeView()
            }
            if app.isLoading {
                ProgressView("Preparing your document…")
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(minWidth: 780, minHeight: 580)
        // The whole window accepts dropped files, on the start screen and while reading.
        .onDrop(of: [.fileURL], isTargeted: $app.isDropTargeted) { providers in
            app.handleDrop(providers)
        }
        .overlay {
            if app.isDropTargeted && app.reader != nil {
                ReaderDropOverlay(theme: app.settings.theme, ui: app.settings.ui)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: app.isDropTargeted)
        .alert(
            "Couldn't open that file",
            isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
        .sheet(isPresented: $app.showComfortSetup) {
            ComfortSetupView()
                .environment(app)
        }
        .sheet(isPresented: $app.showResearch) {
            ResearchView(asSheet: true)
                .environment(app)
                .frame(width: 720, height: 760)
        }
        .sheet(item: $app.codeViewer) { item in
            CodeViewer(item: item)
                .environment(app)
        }
        .sheet(isPresented: $app.showShortcuts) {
            ShortcutsView()
                .environment(app)
        }
    }
}

struct WelcomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let theme = app.settings.theme
        let ui = app.settings.ui

        ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 14) {
                        AppMark(theme: theme)
                            .frame(width: 84, height: 84)
                        Text("Anchor")
                            .font(.system(size: ui * 2.8, weight: .bold, design: .serif))
                        Text("Read long things one small piece at a time.")
                            .font(.system(size: ui * 1.35))
                            .foregroundStyle(theme.secondary)
                    }
                    .padding(.top, 30)

                    DropZone(theme: theme, ui: ui, isTargeted: app.isDropTargeted) {
                        app.showOpenPanel()
                    }
                    .frame(maxWidth: 640)

                    Button {
                        app.openTour()
                    } label: {
                        Label("New here? Take the 3-minute tour", systemImage: "sparkles")
                            .font(.system(size: ui * 1.05))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .controlSize(.large)

                    if !app.settings.s.comfortSetupDone {
                        HStack(spacing: 16) {
                            Image(systemName: "eyeglasses")
                                .font(.system(size: ui * 1.8))
                                .foregroundStyle(theme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("First: make text comfortable for your eyes")
                                    .font(.system(size: ui * 1.1, weight: .semibold))
                                Text("Pick a text size that feels effortless, then a quick test finds the font you read fastest in. About 2 minutes.")
                                    .foregroundStyle(theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Set up") { app.showComfortSetup = true }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.accent)
                                .controlSize(.large)
                        }
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 16).fill(theme.highlight))
                        .frame(maxWidth: 640)
                    }

                    let recents = app.store.recents.prefix(8)
                    if !recents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Continue reading")
                                .font(.system(size: ui * 0.95, weight: .semibold))
                                .foregroundStyle(theme.secondary)
                            ForEach(Array(recents)) { record in
                                RecentRow(record: record, theme: theme, ui: ui)
                            }
                        }
                        .frame(maxWidth: 640)
                    }

                    HStack(spacing: 22) {
                        Button("Reading comfort setup") { app.showComfortSetup = true }
                        Button("Why this works") { app.showResearch = true }
                        Button("Keyboard shortcuts") { app.showShortcuts = true }
                        SettingsLink { Text("Settings") }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.accent)
                    .padding(.bottom, 30)
                }
                .font(.system(size: ui))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .task {
            if !app.settings.s.comfortSetupDone {
                try? await Task.sleep(for: .milliseconds(500))
                app.showComfortSetup = true
            }
        }
    }
}

/// The big "drop a file here" target on the start screen. Click it to choose a file instead.
struct DropZone: View {
    let theme: Theme
    let ui: CGFloat
    let isTargeted: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 14) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: ui * 3, weight: .light))
                    .foregroundStyle(theme.accent)
                    .scaleEffect(isTargeted ? 1.15 : 1)
                Text(isTargeted ? "Let go to open it" : "Drop a file here to start reading")
                    .font(.system(size: ui * 1.35, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text("Markdown · PDF · Word · RTF · HTML · plain text")
                    .font(.system(size: ui * 0.95))
                    .foregroundStyle(theme.secondary)
                Text("or click to choose a file (⌘O)")
                    .font(.system(size: ui * 0.95, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .opacity(isTargeted ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ui * 2.4)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isTargeted ? theme.accent.opacity(0.12) : (hovering ? theme.highlight : theme.highlight.opacity(0.55)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isTargeted ? theme.accent : theme.secondary.opacity(0.45),
                        style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: isTargeted ? [] : [9, 7])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: isTargeted)
        .accessibilityLabel("Drop a file here to start reading, or click to choose a file")
    }
}

/// Shown over the reading view while a file is dragged onto the window.
struct ReaderDropOverlay: View {
    let theme: Theme
    let ui: CGFloat

    var body: some View {
        ZStack {
            theme.background.opacity(0.92)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: ui * 3, weight: .light))
                    .foregroundStyle(theme.accent)
                Text("Drop to read this file")
                    .font(.system(size: ui * 1.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text("Your place in the current document is saved.")
                    .font(.system(size: ui))
                    .foregroundStyle(theme.secondary)
            }
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: 3)
                .padding(24)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct RecentRow: View {
    let record: DocRecord
    let theme: Theme
    let ui: CGFloat
    @Environment(AppState.self) private var app
    @State private var hovering = false

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: record.path)
        Button {
            app.open(URL(fileURLWithPath: record.path))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: ui * 1.3))
                    .foregroundStyle(theme.accent)
                    .frame(width: ui * 1.8)
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.title)
                        .font(.system(size: ui * 1.05, weight: .medium))
                        .lineLimit(1)
                    ProgressView(value: record.progress)
                        .tint(theme.accent)
                        .frame(maxWidth: 260)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(record.progress >= 0.999 ? "Finished" : "\(Int(record.progress * 100))%")
                        .monospacedDigit()
                    Text(record.lastOpened.formatted(.relative(presentation: .named)))
                        .font(.system(size: ui * 0.8))
                        .foregroundStyle(theme.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(hovering ? theme.highlight : theme.highlight.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!exists)
        .opacity(exists ? 1 : 0.45)
        .onHover { hovering = $0 }
        .help(exists ? record.path : "File not found: \(record.path)")
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.path)]) }
            Button("Remove from list", role: .destructive) { app.store.remove(record.path) }
        }
    }

    private var icon: String {
        switch URL(fileURLWithPath: record.path).pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "md", "markdown": "text.alignleft"
        case "docx", "doc", "rtf", "odt": "doc.text"
        default: "doc.plaintext"
        }
    }
}

/// The app's mark: lines of text with one in the spotlight.
struct AppMark: View {
    let theme: Theme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.23, style: .continuous)
                    .fill(theme.highlight)
                VStack(alignment: .leading, spacing: w * 0.075) {
                    line(w, 0.52, opacity: 0.22)
                    HStack(spacing: w * 0.05) {
                        Capsule().fill(theme.accent).frame(width: w * 0.045, height: w * 0.16)
                        line(w, 0.5, opacity: 1)
                    }
                    line(w, 0.42, opacity: 0.22)
                }
            }
        }
    }

    private func line(_ w: CGFloat, _ fraction: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(theme.text.opacity(opacity))
            .frame(width: w * fraction, height: w * 0.085)
    }
}

struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    var body: some View {
        let ui = app.settings.ui
        let rows: [(String, String)] = [
            ("Space  /  →  /  ↓  /  J", "Next bit"),
            ("⇧ Space  /  ←  /  ↑  /  K", "Previous bit"),
            ("D", "I zoned out: step back one bit"),
            ("R", "Read aloud on / off"),
            ("O", "Show the map (outline)"),
            ("N", "Show recall notes"),
            ("Z", "Hide controls (Esc to show)"),
            ("F", "Full screen"),
            ("T", "Pause / resume sprint timer"),
            ("B", "Take a break now"),
            ("⌘ =  /  ⌘ −  /  ⌘ 0", "Bigger / smaller / default text"),
            ("Pinch", "Resize text with the trackpad"),
            ("Click any bit", "Jump there"),
        ]
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard shortcuts")
                .font(.system(size: ui * 1.5, weight: .bold))
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                ForEach(rows, id: \.0) { key, action in
                    GridRow {
                        Text(key)
                            .font(.system(size: ui, weight: .semibold, design: .rounded))
                        Text(action)
                            .font(.system(size: ui))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 560)
    }
}
