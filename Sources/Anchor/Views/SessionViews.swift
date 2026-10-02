import SwiftUI

/// Shown when a document opens: the size of the job, the map, and a 5-minute promise.
struct StartSessionView: View {
    let model: ReaderModel
    @Environment(AppState.self) private var app
    @State private var phoneAway = false
    @State private var dnd = false
    @State private var water = false

    var body: some View {
        @Bindable var settings = app.settings
        let theme = settings.theme
        let ui = settings.ui

        ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.title)
                            .font(.system(size: ui * 1.9, weight: .bold))
                            .lineLimit(3)
                        Text("About \(model.totalMinutes) min at your pace · \(model.sections.count) sections · \(model.totalWords.formatted()) words")
                            .foregroundStyle(theme.secondary)
                    }

                    if model.isResuming {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("You're \(Int(model.resumedFrom * 100))% through. Picking up where you left off.", systemImage: "bookmark.fill")
                                .foregroundStyle(theme.accent)
                            if let note = model.notes.last {
                                Text("Your last note: “\(note.text)”")
                                    .italic()
                                    .foregroundStyle(theme.text.opacity(0.8))
                            }
                        }
                    }

                    let topSections = model.sections.filter { $0.level <= (model.sections.map(\.level).min() ?? 1) + 1 }
                    if !topSections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The map (skim it first, it gives your brain hooks to hang things on)")
                                .font(.system(size: ui * 0.9, weight: .semibold))
                                .foregroundStyle(theme.secondary)
                            FlowLayout(spacing: 8) {
                                ForEach(topSections.prefix(14)) { section in
                                    Text(section.title)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(theme.highlight))
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sprint length")
                            .font(.system(size: ui * 0.9, weight: .semibold))
                            .foregroundStyle(theme.secondary)
                        HStack(spacing: 8) {
                            ForEach([3, 5, 10, 15, 25], id: \.self) { minutes in
                                ChoiceChip(label: "\(minutes) min", selected: settings.s.sprintMinutes == minutes, theme: theme) {
                                    settings.s.sprintMinutes = minutes
                                }
                            }
                        }
                        Text("Start where you are. When \(settings.s.sprintMinutes) minutes starts to feel easy, try a little longer.")
                            .font(.system(size: ui * 0.85))
                            .foregroundStyle(theme.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Before you start")
                            .font(.system(size: ui * 0.9, weight: .semibold))
                            .foregroundStyle(theme.secondary)
                        CheckRow(isOn: $phoneAway, text: "Phone in another room. Even face-down on the desk, it drains attention.", theme: theme)
                        CheckRow(isOn: $dnd, text: "Do Not Disturb on (Control Center → Focus).", theme: theme)
                        CheckRow(isOn: $water, text: "Water nearby, so you don't have to get up.", theme: theme)
                    }

                    HStack(spacing: 14) {
                        Button {
                            model.startSession()
                        } label: {
                            Text(model.isResuming ? "Continue: \(settings.s.sprintMinutes)-minute sprint" : "Start a \(settings.s.sprintMinutes)-minute sprint")
                                .font(.system(size: ui * 1.1, weight: .semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                        .controlSize(.large)
                        Text("or press Space")
                            .foregroundStyle(theme.secondary)
                    }

                    KeyHints(theme: theme, ui: ui)
                }
                .font(.system(size: ui))
                .foregroundStyle(theme.text)
                .padding(40)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct KeyHints: View {
    let theme: Theme
    let ui: CGFloat

    var body: some View {
        let hints: [(String, String)] = [
            ("Space", "next bit"), ("⇧ Space", "back"), ("D", "I zoned out"),
            ("R", "read aloud"), ("O", "map"), ("Z", "hide controls"), ("⌘ + / −", "text size"),
        ]
        FlowLayout(spacing: 14) {
            ForEach(hints, id: \.0) { key, action in
                HStack(spacing: 6) {
                    Text(key)
                        .font(.system(size: ui * 0.85, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.secondary.opacity(0.5)))
                    Text(action)
                        .font(.system(size: ui * 0.85))
                }
                .fixedSize()
                .foregroundStyle(theme.secondary)
            }
        }
    }
}

struct ChoiceChip: View {
    let label: String
    let selected: Bool
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? theme.background : theme.text)
                .background(Capsule().fill(selected ? theme.accent : theme.highlight))
        }
        .buttonStyle(.plain)
    }
}

struct CheckRow: View {
    @Binding var isOn: Bool
    let text: String
    let theme: Theme

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? theme.accent : theme.secondary)
                Text(text)
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Full-screen break. Text is hidden so the break is actually a break.
struct BreakOverlay: View {
    let model: ReaderModel
    @Environment(AppState.self) private var app
    @State private var tip = BreakTips.all.randomElement() ?? BreakTips.all[0]

    var body: some View {
        let theme = app.settings.theme
        let ui = app.settings.ui
        let timer = model.timer

        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                if timer.phase == .onBreak {
                    Text("Break time")
                        .font(.system(size: ui * 2.2, weight: .bold))
                    Text(timer.remaining.mmss)
                        .font(.system(size: 76, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                    Text(tip)
                        .font(.system(size: ui * 1.25))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    Button("Skip the break") { timer.skipBreak() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(theme.secondary)
                } else {
                    Text("Ready for another round?")
                        .font(.system(size: ui * 2.2, weight: .bold))
                    if let next = model.nextSectionTitle {
                        Text("Next up: \(next)")
                            .font(.system(size: ui * 1.2))
                            .foregroundStyle(theme.secondary)
                    }
                    HStack(spacing: 14) {
                        Button {
                            model.resumeAfterBreak()
                        } label: {
                            Text("Start \(app.settings.s.sprintMinutes)-minute sprint")
                                .font(.system(size: ui * 1.1, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                        .controlSize(.large)
                        Button("Done for now") { model.finish() }
                            .controlSize(.large)
                    }
                    Text("Press Return to start")
                        .foregroundStyle(theme.secondary)
                }

                if let note = model.notes.last {
                    VStack(spacing: 6) {
                        Text("Your last recall note")
                            .font(.system(size: ui * 0.85, weight: .semibold))
                            .foregroundStyle(theme.secondary)
                        Text("“\(note.text)”")
                            .italic()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                    }
                    .padding(.top, 10)
                }

                if timer.completedSprints > 0 {
                    Text(timer.completedSprints == 1 ? "1 sprint done this session" : "\(timer.completedSprints) sprints done this session")
                        .font(.system(size: ui * 0.9))
                        .foregroundStyle(theme.secondary)
                }
            }
            .font(.system(size: ui))
            .foregroundStyle(theme.text)
            .padding(40)
        }
    }
}

enum BreakTips {
    static let all = [
        "Look at something far away, out a window if you can. Give your eyes a rest from the screen.",
        "Stand up, stretch your arms over your head, roll your shoulders.",
        "Get a glass of water.",
        "Take five slow breaths. In through the nose, out through the mouth.",
        "Try not to pick up your phone. A one-minute break easily turns into twenty.",
        "Close your eyes and replay what you just read in one sentence.",
        "Walk to another room and back.",
    ]
}

struct SessionSummaryView: View {
    let model: ReaderModel
    @Environment(AppState.self) private var app

    var body: some View {
        let theme = app.settings.theme
        let ui = app.settings.ui
        let minutes = Int((model.timer.focusedSeconds / 60).rounded())
        let atEnd = model.index >= model.chunks.count - 1

        ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 26) {
                    Image(systemName: atEnd ? "checkmark.seal.fill" : "leaf.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(theme.accent)
                    Text(atEnd ? "You finished it." : "Nice work.")
                        .font(.system(size: ui * 2.2, weight: .bold))
                    Text(atEnd ? "The whole thing, one small piece at a time." : "Stopping on purpose is a skill too. Your place is saved.")
                        .font(.system(size: ui * 1.15))
                        .foregroundStyle(theme.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 14) {
                        Stat(value: minutes < 1 ? "<1" : "\(minutes)", label: "minutes focused", theme: theme, ui: ui)
                        Stat(value: "\(model.timer.completedSprints)", label: "sprints", theme: theme, ui: ui)
                        Stat(value: model.sessionWords.formatted(), label: "words read", theme: theme, ui: ui)
                        Stat(value: "\(model.sessionNotes)", label: "recall notes", theme: theme, ui: ui)
                        Stat(value: "\(model.driftCount)", label: "drifts caught", theme: theme, ui: ui)
                    }

                    VStack(spacing: 6) {
                        ProgressView(value: model.progress)
                            .tint(theme.accent)
                            .frame(maxWidth: 420)
                        Text("\(Int((model.progress * 100).rounded()))% of the document")
                            .foregroundStyle(theme.secondary)
                    }

                    if model.driftCount > 0 {
                        Text("Every time you pressed D, you noticed your mind wander and brought it back. That's the exact skill that gets stronger with practice.")
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                            .foregroundStyle(theme.text.opacity(0.85))
                    }

                    HStack(spacing: 12) {
                        if !atEnd {
                            Button("Keep reading") { model.keepReading() }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.accent)
                        }
                        if !model.notes.isEmpty {
                            Button("Export notes…") { model.exportNotes() }
                        }
                        Button("Close document") { app.closeDocument() }
                    }
                    .controlSize(.large)
                }
                .font(.system(size: ui))
                .foregroundStyle(theme.text)
                .padding(48)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct Stat: View {
    let value: String
    let label: String
    let theme: Theme
    let ui: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: ui * 1.8, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: ui * 0.8))
                .foregroundStyle(theme.secondary)
        }
        .frame(minWidth: 96)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.highlight))
    }
}

struct NotesInspector: View {
    let model: ReaderModel
    @Environment(AppState.self) private var app

    var body: some View {
        let ui = app.settings.ui
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recall notes")
                    .font(.system(size: ui * 1.15, weight: .semibold))
                Spacer()
                Menu {
                    Button("Export as Markdown…") { model.exportNotes() }
                    Button("Copy all") { model.copyNotes() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.notes.isEmpty)
            }
            .padding(16)

            if model.notes.isEmpty {
                ContentUnavailableView(
                    "No notes yet",
                    systemImage: "note.text",
                    description: Text("At the end of each section, Anchor asks you to sum it up in one sentence. Your answers collect here.")
                )
            } else {
                List {
                    ForEach(model.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.section)
                                .font(.system(size: ui * 0.8, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(note.text)
                                .font(.system(size: ui))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Delete", role: .destructive) { model.deleteNote(note.id) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

/// Wraps children onto new lines when they run out of width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
