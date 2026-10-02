import AppKit
import SwiftUI

struct ReaderScreen: View {
    @Bindable var model: ReaderModel
    @Environment(AppState.self) private var app
    @State private var showType = false

    var body: some View {
        let settings = app.settings.s
        let theme = settings.theme.palette

        NavigationSplitView(columnVisibility: Binding(
            get: { model.showOutline ? .all : .detailOnly },
            set: { model.showOutline = $0 != .detailOnly }
        )) {
            OutlineView(model: model)
        } detail: {
            ZStack {
                theme.background.ignoresSafeArea()

                ReaderScroll(model: model, style: TextStyle(settings), settings: settings)

                if !model.zen {
                    VStack {
                        Spacer()
                        HUDView(model: model, theme: theme, ui: app.settings.ui)
                    }
                }

                VStack(spacing: 10) {
                    if let toast = model.toast {
                        ToastView(text: toast, theme: theme, ui: app.settings.ui)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if model.suggestBreak {
                        BreakSuggestion(model: model, theme: theme, ui: app.settings.ui)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(.top, 14)
                .animation(.spring(duration: 0.35), value: model.toast)
                .animation(.spring(duration: 0.35), value: model.suggestBreak)

                if model.phase == .starting {
                    StartSessionView(model: model)
                        .transition(.opacity)
                }
                if model.timer.isOnBreak {
                    BreakOverlay(model: model)
                        .transition(.opacity)
                }
                if model.phase == .finished {
                    SessionSummaryView(model: model)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: model.phase)
            .animation(.easeInOut(duration: 0.3), value: model.timer.isOnBreak)
            .inspector(isPresented: $model.showNotes) {
                NotesInspector(model: model)
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
            }
            .toolbar(model.zen ? .hidden : .automatic, for: .windowToolbar)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showType.toggle() } label: {
                        Label("Text size & style", systemImage: "textformat.size")
                    }
                    .help("Text size, font, spacing and colors")
                    .popover(isPresented: $showType, arrowEdge: .bottom) {
                        TypographyControls(compact: true)
                            .environment(app)
                            .frame(width: 380, height: 520)
                    }

                    Button { model.toggleReadAloud() } label: {
                        Label("Read aloud", systemImage: model.readAloud ? "speaker.wave.2.fill" : "speaker.wave.2")
                    }
                    .help("Read aloud with word highlighting (R)")

                    Button { model.showNotes.toggle() } label: {
                        Label("Recall notes", systemImage: "note.text")
                    }
                    .help("Your recall notes (N)")

                    Button { model.zen = true } label: {
                        Label("Hide controls", systemImage: "eye.slash")
                    }
                    .help("Hide everything but the text (Z). Esc brings it back.")

                    Button { model.finish() } label: {
                        Label("End session", systemImage: "flag.checkered")
                    }
                    .help("End this session and see your summary")
                }
            }
        }
        .navigationTitle(model.title)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(isPresented: $model.showCheckpoint, onDismiss: { model.checkpointDismissed() }) {
            CheckpointSheet(model: model)
                .environment(app)
        }
        .background(WindowReader { window in
            model.window = window
        })
        .onAppear { model.installKeyMonitor() }
        .onChange(of: settings.chunkSize) { model.rechunk() }
    }
}

struct ReaderScroll: View {
    let model: ReaderModel
    let style: TextStyle
    let settings: ReaderSettings
    @State private var pinchBase: Double?
    @State private var viewportHeight: CGFloat = 700
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geo in
            // Height a bite can use without hiding under the toolbar or the bottom bar.
            let usableHeight = geo.size.height * (1 - Self.topInset) - (model.zen ? 0 : 56) - 12
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .center, spacing: 0) {
                        Color.clear.frame(height: max(80, geo.size.height * 0.28))
                        ForEach(model.chunks) { chunk in
                            ChunkView(
                                chunk: chunk,
                                isCurrent: chunk.id == model.index,
                                opacity: opacity(for: chunk.id),
                                style: style,
                                spotlight: settings.spotlight,
                                speaker: model.speaker,
                                availableWidth: max(320, geo.size.width - 64),
                                onHeight: { model.reportHeight($0, for: chunk.id) }
                            )
                            .padding(.top, chunk.id == 0 ? 0 : (chunk.startsParagraph ? style.size * 1.1 : style.size * 0.35))
                            .id(chunk.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.jump(to: chunk.id) }
                        }
                        Color.clear.frame(height: geo.size.height * 0.6)
                    }
                    // Each chunk sizes itself: prose to the comfortable text column,
                    // tables as wide as they need (up to the window).
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.index) { scroll(proxy, animated: true) }
                .onChange(of: model.page) { scroll(proxy, animated: true) }
                .onChange(of: model.pageCount) { scroll(proxy, animated: true) }
                .onChange(of: settings) { scroll(proxy, animated: false) }
                .onChange(of: model.chunks.count) { scroll(proxy, animated: false) }
                // Sidebar, notes panel or window resize changed the line wrapping.
                .onChange(of: geo.size) { scroll(proxy, animated: false) }
                .onChange(of: usableHeight, initial: true) {
                    model.usableHeight = usableHeight
                    viewportHeight = geo.size.height
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(60))
                    scroll(proxy, animated: false)
                }
            }
        }
        // Pinch to resize text on a trackpad.
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let base = pinchBase ?? app.settings.s.fontSize
                    pinchBase = base
                    let size = (base * value.magnification).rounded()
                    app.settings.s.fontSize = min(max(size, ReaderSettings.minFontSize), ReaderSettings.maxFontSize)
                }
                .onEnded { _ in pinchBase = nil }
        )
    }

    static let topInset: CGFloat = 0.03

    /// Normal bites sit a little above the middle of the window. A bite taller than the
    /// window is shown from its top, one screenful at a time.
    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        let viewport = viewportHeight
        let action = {
            if model.pageCount > 1, let height = model.currentHeight {
                // scrollTo lines up the point at `y` of the bite with the point at `y` of the
                // window. Solve for the y that puts this screenful's start just under the top.
                let offsets = ChunkPaging.offsets(height: height, usable: model.usableHeight)
                let start = offsets[min(model.page, offsets.count - 1)]
                var span = height - viewport
                if abs(span) < 1 { span = 1 }
                let y = (start - Self.topInset * viewport) / span
                proxy.scrollTo(model.index, anchor: UnitPoint(x: 0.5, y: y))
            } else {
                proxy.scrollTo(model.index, anchor: UnitPoint(x: 0.5, y: 0.36))
            }
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.35), action)
        } else {
            action()
        }
    }

    private func opacity(for id: Int) -> Double {
        let distance = abs(id - model.index)
        if distance == 0 { return 1 }
        let dim = settings.dimLevel
        return distance == 1 ? min(1, dim + 0.12) : dim
    }
}

struct ChunkView: View {
    let chunk: Chunk
    let isCurrent: Bool
    let opacity: Double
    let style: TextStyle
    let spotlight: Bool
    let speaker: Speaker
    let availableWidth: CGFloat
    let onHeight: (CGFloat) -> Void

    var body: some View {
        let highlight = isCurrent ? speaker.highlight : nil
        let inset = style.size * 0.6
        var layouts: [Int: TableLayout] = [:]
        var codeLayouts: [Int: CodeLayout] = [:]
        for segment in chunk.segments {
            if let table = segment.table {
                layouts[segment.id] = TableLayout.compute(table, style: style, available: availableWidth - inset * 2)
            } else if case .code = segment.kind {
                codeLayouts[segment.id] = CodeLayout.compute(segment.plain, style: style, available: availableWidth - inset * 2)
            }
        }
        // Prose keeps the comfortable column; tables and code may widen past it so nothing is cut off.
        let widest = (layouts.values.filter { !$0.useCards }.map(\.gridWidth) + codeLayouts.values.map(\.width)).max()
        let maxWidth = widest.map { max(style.columnWidth, min($0 + inset * 2, availableWidth)) } ?? style.columnWidth

        return VStack(alignment: .leading, spacing: style.size * 0.4) {
            ForEach(chunk.segments) { segment in
                let mine = highlight?.segmentID == segment.id ? highlight : nil
                SegmentView(
                    segment: segment,
                    style: style,
                    highlight: mine?.row == nil ? mine?.range : nil,
                    tableLayout: layouts[segment.id],
                    codeLayout: codeLayouts[segment.id],
                    highlightRow: mine?.row
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, style.size * 0.32)
        .padding(.horizontal, inset)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent && spotlight ? style.theme.highlight : .clear)
        )
        .overlay(alignment: .leading) {
            if isCurrent && spotlight {
                Capsule()
                    .fill(style.theme.accent)
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .offset(x: -10)
            }
        }
        .frame(maxWidth: maxWidth)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        .opacity(opacity)
        .animation(.easeOut(duration: 0.25), value: isCurrent)
        .animation(.easeOut(duration: 0.25), value: opacity)
    }
}

/// Splits a bite taller than the window into screenfuls that Space steps through.
enum ChunkPaging {
    /// Where each screenful starts, measured from the bite's top.
    static func offsets(height: CGFloat, usable: CGFloat) -> [CGFloat] {
        guard usable > 120, height > usable + 4 else { return [0] }
        let step = usable * 0.82
        let last = height - usable
        var offsets: [CGFloat] = [0]
        var offset = step
        while offset < last - step * 0.2 {
            offsets.append(offset)
            offset += step
        }
        offsets.append(last)
        return offsets
    }
}

struct SegmentView: View {
    let segment: Segment
    let style: TextStyle
    let highlight: NSRange?
    var tableLayout: TableLayout?
    var codeLayout: CodeLayout?
    var highlightRow: Int?

    var body: some View {
        switch segment.kind {
        case .heading(let level):
            Text(style.styled(segment, highlight: highlight))
                .font(style.heading(level))
                .fontWeight(.bold)
                .foregroundStyle(style.theme.text)
                .lineSpacing(style.lineExtra * 0.6)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph:
            prose(Text(style.styled(segment, highlight: highlight)))

        case .quote:
            HStack(alignment: .top, spacing: style.size * 0.6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(style.theme.accent.opacity(0.55))
                    .frame(width: 4)
                prose(Text(style.styled(segment, highlight: highlight)).italic())
            }

        case .listItem(let marker, let level):
            HStack(alignment: .firstTextBaseline, spacing: style.size * 0.45) {
                Text(marker)
                    .font(style.body)
                    .foregroundStyle(style.theme.accent)
                    .frame(minWidth: style.size * 1.1, alignment: .trailing)
                prose(Text(style.styled(segment, highlight: highlight)))
            }
            .padding(.leading, CGFloat(level) * style.size * 1.3)

        case .table where segment.table != nil && tableLayout != nil:
            TableView(table: segment.table!, layout: tableLayout!, style: style, highlightRow: highlightRow)

        case .code where codeLayout != nil:
            CodeBlockView(text: segment.text, layout: codeLayout!, style: style)

        case .code, .table:
            // Fallback only; code and tables normally use the layouts above.
            ScrollView(.horizontal, showsIndicators: true) {
                Text(segment.text)
                    .font(.system(size: style.codeSize, design: .monospaced))
                    .foregroundStyle(style.theme.text)
                    .lineSpacing(4)
                    .fixedSize()
                    .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.theme.codeBackground)
            )
        }
    }

    private func prose(_ text: Text) -> some View {
        text
            .font(style.body)
            .foregroundStyle(style.theme.text)
            .lineSpacing(style.lineExtra)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Gives the model a handle on its window so keyboard shortcuts only fire there.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Task { @MainActor in onWindow(view.window) }
    }
}

struct ToastView: View {
    let text: String
    let theme: Theme
    let ui: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: ui, weight: .medium))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(theme.highlight))
            .overlay(Capsule().strokeBorder(theme.accent.opacity(0.35)))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

struct BreakSuggestion: View {
    let model: ReaderModel
    let theme: Theme
    let ui: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cup.and.saucer")
            Text("Want a short break? It usually helps more than pushing through.")
            Button("Take a break") { model.takeBreakNow() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            Button("Not now") { model.suggestBreak = false }
                .buttonStyle(.borderless)
        }
        .font(.system(size: ui))
        .foregroundStyle(theme.text)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.highlight))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}
