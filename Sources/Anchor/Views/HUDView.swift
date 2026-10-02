import SwiftUI

/// The quiet bar at the bottom: where you are, how long is left, and the sprint clock.
struct HUDView: View {
    let model: ReaderModel
    let theme: Theme
    let ui: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ProgressTrack(model: model, theme: theme)
            ViewThatFits(in: .horizontal) {
                row(compact: false)
                row(compact: true)
            }
            .font(.system(size: ui))
            .foregroundStyle(theme.secondary)
            .buttonStyle(.borderless)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .animation(.easeInOut, value: model.nudge)
        }
        .background(theme.background.opacity(0.95))
    }

    /// Full labels when there's room; icons only when the window is narrow.
    private func row(compact: Bool) -> some View {
        HStack(spacing: 12) {
            if !compact {
                Text(model.currentSectionTitle ?? model.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(theme.text.opacity(0.75))
                    .frame(maxWidth: 280, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text("\(Int((model.progress * 100).rounded()))%")
                .monospacedDigit()
            Text(compact ? "~\(model.minutesLeft)m" : "~\(model.minutesLeft) min left")
                .monospacedDigit()

            Spacer(minLength: 8)

            if model.pageCount > 1 {
                let more = model.page + 1 < model.pageCount
                Label(compact ? "\(model.page + 1)/\(model.pageCount)" : "Part \(model.page + 1) of \(model.pageCount) · " + (more ? "Space for more" : "Space to move on"),
                      systemImage: more ? "arrow.down.circle" : "checkmark.circle")
                    .foregroundStyle(theme.accent)
                    .monospacedDigit()
            }

            if model.nudge {
                Label(compact ? "Still with me?" : "Still with me? Space to go on, D to re-read", systemImage: "hand.wave")
                    .foregroundStyle(theme.accent)
                    .transition(.opacity)
            }

            Button(action: model.zonedOut) {
                Label("Zoned out", systemImage: "arrow.uturn.backward")
            }
            .help("Lost focus? Press D to step back one bit. No judgement.")

            Button(action: model.toggleReadAloud) {
                Label(model.readAloud ? "Stop" : "Read aloud", systemImage: model.readAloud ? "stop.circle" : "speaker.wave.2")
            }
            .help("Read aloud with word highlighting (R)")

            TimerPill(model: model, theme: theme)
        }
        .labelStyle(CompactAwareLabelStyle(compact: compact))
        .lineLimit(1)
        .fixedSize(horizontal: compact, vertical: false)
    }
}

struct CompactAwareLabelStyle: LabelStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            if !compact { configuration.title }
        }
        .fixedSize()
    }
}

struct ProgressTrack: View {
    let model: ReaderModel
    let theme: Theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.secondary.opacity(0.15))
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: geo.size.width * model.progress)
                    .animation(.easeOut(duration: 0.3), value: model.progress)
                // Section ticks, so you can see how far the next "finish line" is.
                ForEach(model.sections.filter { $0.level <= 2 }) { section in
                    if model.chunks.indices.contains(section.chunkIndex), model.totalWords > 0 {
                        let x = geo.size.width * Double(model.chunks[section.chunkIndex].wordOffset) / Double(model.totalWords)
                        Rectangle()
                            .fill(theme.background)
                            .frame(width: 2)
                            .offset(x: x)
                    }
                }
            }
        }
        .frame(height: 4)
    }
}

struct TimerPill: View {
    let model: ReaderModel
    let theme: Theme

    var body: some View {
        let timer = model.timer
        Menu {
            Button(timer.userPaused ? "Resume timer" : "Pause timer") { timer.togglePause() }
            Button("Take a break now") { model.takeBreakNow() }
            if timer.phase == .sprintDone {
                Button("I'm in the zone: +2 minutes") { model.keepGoing(minutes: 2) }
                Button("I'm in the zone: +5 minutes") { model.keepGoing(minutes: 5) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(timer))
                Text(label(timer))
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(timer.phase == .sprintDone ? theme.background : theme.text)
            .background(
                Capsule().fill(timer.phase == .sprintDone ? theme.accent : theme.highlight)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sprint timer (T to pause)")
    }

    private func icon(_ timer: SprintTimer) -> String {
        if timer.isPaused { return "pause.circle" }
        return timer.phase == .sprintDone ? "cup.and.saucer.fill" : "timer"
    }

    private func label(_ timer: SprintTimer) -> String {
        switch timer.phase {
        case .sprintDone: "Break after this bit"
        case .sprint: timer.isPaused ? "Paused \(timer.remaining.mmss)" : timer.remaining.mmss
        default: "–:––"
        }
    }
}

struct OutlineView: View {
    let model: ReaderModel
    @Environment(AppState.self) private var app

    var body: some View {
        let minLevel = model.sections.map(\.level).min() ?? 1
        let current = model.currentSectionIndex
        List {
            Section("Map of this document") {
                ForEach(model.sections) { section in
                    let done = current.map { section.id < $0 } ?? false
                    let isCurrent = section.id == current
                    Button {
                        model.jump(to: section.chunkIndex)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: done ? "checkmark.circle.fill" : (isCurrent ? "circle.inset.filled" : "circle"))
                                .foregroundStyle(done || isCurrent ? Color.accentColor : .secondary)
                            Text(section.title)
                                .fontWeight(isCurrent ? .semibold : .regular)
                                .lineLimit(3)
                        }
                        .padding(.leading, CGFloat(section.level - minLevel) * 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.system(size: app.settings.ui))
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 380)
        .overlay {
            if model.sections.isEmpty {
                ContentUnavailableView("No headings", systemImage: "list.bullet.indent", description: Text("This document doesn't have sections."))
            }
        }
    }
}

struct CheckpointSheet: View {
    let model: ReaderModel
    @Environment(AppState.self) private var app
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let ui = app.settings.ui
        VStack(alignment: .leading, spacing: 16) {
            Label("Quick recall", systemImage: "brain.head.profile")
                .font(.system(size: ui * 1.5, weight: .bold))
            Text(model.checkpointTitle.isEmpty ? "What was that last part about?" : "What was “\(model.checkpointTitle)” about?")
                .font(.system(size: ui * 1.2, weight: .medium))
            Text("One sentence in your own words is plenty. Pulling it back from memory is what makes it stick, and it reels a drifting mind back in.")
                .font(.system(size: ui))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(size: ui * 1.1))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 110)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .focused($focused)
            HStack {
                Button("Re-read section") { model.rereadSection() }
                Spacer()
                Button("I said it in my head") { model.completeCheckpoint(note: nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Save & continue") { model.completeCheckpoint(note: text) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.system(size: ui))
            .controlSize(.large)
            Text("⌘↩ saves · Esc skips")
                .font(.system(size: ui * 0.8))
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 580)
        .onAppear { focused = true }
    }
}
