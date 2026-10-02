import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ReaderPhase: Equatable {
    case starting
    case reading
    case finished
}

/// One open document and everything about the current reading session.
@Observable
final class ReaderModel {
    let docKey: String?
    let title: String
    let language: String?
    @ObservationIgnored private let blocks: [Block]

    private(set) var chunks: [Chunk] = []
    private(set) var sections: [DocSection] = []
    private(set) var totalWords = 0
    private(set) var index = 0
    /// For a bite taller than the window: which screenful is showing, and how many there are.
    private(set) var page = 0
    private(set) var pageCount = 1

    var phase: ReaderPhase = .starting
    var showCheckpoint = false
    private(set) var checkpointTitle = ""
    var readAloud = false
    var zen = false
    var showOutline = false
    var showNotes = false
    private(set) var toast: String?
    private(set) var nudge = false
    var suggestBreak = false
    private(set) var sampleNotes: [Note] = []

    // Session stats
    let sessionStart = Date()
    private(set) var sessionWords = 0
    private(set) var driftCount = 0
    private(set) var sessionNotes = 0
    private(set) var wordsPerMinute: Double = 200
    let resumedFrom: Double

    let timer = SprintTimer()
    let speaker = Speaker()
    let settings: SettingsStore
    let store: ProgressStore
    @ObservationIgnored weak var window: NSWindow?

    @ObservationIgnored private var chunkHeights: [Int: CGFloat] = [:]
    /// Height a bite can use on screen; set by the reading view.
    @ObservationIgnored var usableHeight: CGFloat = 600 {
        didSet { if oldValue != usableHeight { refreshPages() } }
    }
    @ObservationIgnored private var pendingTarget: Int?
    @ObservationIgnored private var wordsSinceCheckpoint = 0
    @ObservationIgnored private var sprintDrifts = 0
    @ObservationIgnored private var furthest = 0
    @ObservationIgnored private var chunkEnteredAt = Date()
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var awaySince: Date?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var recordedFocus: TimeInterval = 0
    @ObservationIgnored private var recordedSprints = 0

    init(document: LoadedDocument, key: String?, initial: Chunker.Output, settings: SettingsStore, store: ProgressStore) {
        self.docKey = key
        self.title = document.title
        self.language = document.language
        self.blocks = document.blocks
        self.settings = settings
        self.store = store

        let record = key.flatMap { store.record($0) }
        resumedFrom = record?.progress ?? 0
        if let wpm = record?.wpm { wordsPerMinute = wpm }

        apply(initial, keepingWordOffset: record?.wordOffset ?? 0)

        speaker.onFinishedChunk = { [weak self] in self?.speechFinishedChunk() }
        timer.onSprintEnded = { [weak self] in self?.sprintEnded() }
        timer.onBreakEnded = { [weak self] in self?.breakEnded() }
        startHeartbeat()
        observeAppActivity()
        persist()
    }

    // MARK: - Derived

    var currentChunk: Chunk? { chunks.indices.contains(index) ? chunks[index] : nil }

    var currentSectionIndex: Int? { currentChunk?.sectionIndex }

    var currentSectionTitle: String? {
        currentSectionIndex.map { sections[$0].title }
    }

    var progress: Double {
        guard totalWords > 0, let chunk = currentChunk else { return 0 }
        return min(1, Double(chunk.wordOffset) / Double(totalWords))
    }

    var minutesLeft: Int {
        guard let chunk = currentChunk else { return 0 }
        let remaining = max(totalWords - chunk.wordOffset, 0)
        return max(1, Int((Double(remaining) / max(wordsPerMinute, 60)).rounded(.up)))
    }

    var totalMinutes: Int { max(1, Int((Double(totalWords) / max(wordsPerMinute, 60)).rounded(.up))) }

    var notes: [Note] {
        guard let key = docKey else { return sampleNotes }
        return store.record(key)?.notes ?? []
    }

    var isResuming: Bool { resumedFrom > 0.01 }

    var nextSectionTitle: String? {
        let target = pendingTarget ?? index
        guard chunks.indices.contains(target) else { return nil }
        if let s = chunks[target].sectionIndex { return sections[s].title }
        return nil
    }

    // MARK: - Session flow

    func startSession() {
        guard phase == .starting else { return }
        phase = .reading
        timer.configure(sprintMinutes: settings.s.sprintMinutes, breakMinutes: settings.s.breakMinutes)
        timer.startSprint()
        chunkEnteredAt = Date()
        activity()
        if readAloud { speakCurrent() }
    }

    func primaryAction() {
        switch phase {
        case .starting:
            startSession()
        case .finished:
            break
        case .reading:
            if timer.phase == .breakDone {
                resumeAfterBreak()
            } else if timer.phase != .onBreak {
                next()
            }
        }
    }

    /// Space: shows the rest of a tall bite first, then moves to the next bite.
    func next() {
        guard phase == .reading, !chunks.isEmpty, !timer.isOnBreak, !showCheckpoint else { return }
        if page + 1 < pageCount {
            activity()
            page += 1
            return
        }
        advance()
    }

    private func advance() {
        guard phase == .reading, !chunks.isEmpty, !timer.isOnBreak, !showCheckpoint else { return }
        activity()
        measurePace()
        if index >= furthest {
            wordsSinceCheckpoint += chunks[index].wordCount
            sessionWords += chunks[index].wordCount
        }
        proceed(to: index + 1)
    }

    func previous() {
        guard phase == .reading, !timer.isOnBreak, !showCheckpoint else { return }
        if page > 0 {
            activity()
            page -= 1
            return
        }
        guard index > 0 else { return }
        activity()
        go(to: index - 1)
    }

    var currentHeight: CGFloat? { chunkHeights[index] }

    /// Called by the view with each bite's laid-out height.
    func reportHeight(_ height: CGFloat, for chunk: Int) {
        guard chunkHeights[chunk] != height else { return }
        chunkHeights[chunk] = height
        if chunk == index { refreshPages() }
    }

    private func refreshPages() {
        let count = ChunkPaging.offsets(height: chunkHeights[index] ?? 0, usable: usableHeight).count
        if pageCount != count { pageCount = count }
        if page > count - 1 { page = count - 1 }
    }

    func jump(to target: Int) {
        guard phase == .reading, !timer.isOnBreak, !showCheckpoint else { return }
        activity()
        go(to: target)
    }

    private func proceed(to target: Int) {
        if checkpointDue(before: target) {
            presentCheckpoint(then: target)
            return
        }
        if timer.phase == .sprintDone {
            beginBreak(then: target)
            return
        }
        if target >= chunks.count {
            finish()
            return
        }
        go(to: target)
    }

    private func go(to target: Int) {
        guard !chunks.isEmpty else { return }
        index = max(0, min(target, chunks.count - 1))
        page = 0
        refreshPages()
        furthest = max(furthest, index)
        chunkEnteredAt = Date()
        persist()
        if readAloud { speakCurrent() } else { speaker.stop() }
    }

    func finish() {
        speaker.stop()
        readAloud = false
        showCheckpoint = false
        timer.stop()
        phase = .finished
        persist()
    }

    func keepReading() {
        phase = .reading
        timer.configure(sprintMinutes: settings.s.sprintMinutes, breakMinutes: settings.s.breakMinutes)
        timer.startSprint()
        activity()
        chunkEnteredAt = Date()
    }

    // MARK: - Recall checkpoints

    private func checkpointDue(before target: Int) -> Bool {
        let words = wordsSinceCheckpoint
        switch settings.s.checkpoints {
        case .off:
            return false
        case .sections:
            if target >= chunks.count { return words >= 80 }
            let next = chunks[target]
            return (next.isHeading && words >= 150) || (words >= 600 && next.startsParagraph)
        case .frequent:
            if target >= chunks.count { return words >= 50 }
            let next = chunks[target]
            return (next.isHeading && words >= 60) || (words >= 250 && next.startsParagraph)
        }
    }

    private func presentCheckpoint(then target: Int) {
        speaker.stop()
        pendingTarget = target
        checkpointTitle = currentSectionTitle ?? ""
        showCheckpoint = true
    }

    func completeCheckpoint(note: String?) {
        guard pendingTarget != nil || showCheckpoint else { return }
        if let text = note?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            addNote(text, section: checkpointTitle)
        }
        wordsSinceCheckpoint = 0
        showCheckpoint = false
        let target = pendingTarget ?? index + 1
        pendingTarget = nil
        activity()
        proceed(to: target)
    }

    func rereadSection() {
        showCheckpoint = false
        pendingTarget = nil
        wordsSinceCheckpoint = 0
        activity()
        go(to: sectionStart(for: index))
    }

    /// Called when the checkpoint sheet is dismissed by any route (e.g. Escape).
    func checkpointDismissed() {
        if pendingTarget != nil { completeCheckpoint(note: nil) }
    }

    private func sectionStart(for chunkIndex: Int) -> Int {
        guard chunks.indices.contains(chunkIndex), let s = chunks[chunkIndex].sectionIndex else { return 0 }
        return min(sections[s].chunkIndex + 1, chunks.count - 1)
    }

    // MARK: - Notes

    func addNote(_ text: String, section: String) {
        let note = Note(section: section.isEmpty ? title : section, text: text)
        sessionNotes += 1
        if let key = docKey {
            store.update(key, title: title) { $0.notes.append(note) }
        } else {
            sampleNotes.append(note)
        }
    }

    func deleteNote(_ id: UUID) {
        if let key = docKey {
            store.update(key, title: title) { $0.notes.removeAll { $0.id == id } }
        } else {
            sampleNotes.removeAll { $0.id == id }
        }
    }

    var notesMarkdown: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        var out = "# Notes on \(title)\n\n_Recall notes from Anchor, \(formatter.string(from: Date()))_\n"
        var lastSection = ""
        for note in notes {
            if note.section != lastSection {
                out += "\n## \(note.section)\n\n"
                lastSection = note.section
            }
            out += "- \(note.text)\n"
        }
        return out
    }

    func exportNotes() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title) – notes.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? notesMarkdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func copyNotes() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notesMarkdown, forType: .string)
        showToast("Notes copied")
    }

    // MARK: - Breaks

    private func sprintEnded() {
        if settings.s.sounds { NSSound(named: "Glass")?.play() }
        showToast("Sprint done. Finish this bit, then take a break.", seconds: 5)
    }

    private func breakEnded() {
        if settings.s.sounds { NSSound(named: "Glass")?.play() }
    }

    private func beginBreak(then target: Int) {
        speaker.stop()
        pendingTarget = target
        sprintDrifts = 0
        suggestBreak = false
        timer.startBreak()
    }

    func takeBreakNow() {
        guard phase == .reading, !timer.isOnBreak else { return }
        beginBreak(then: index)
    }

    func resumeAfterBreak() {
        timer.configure(sprintMinutes: settings.s.sprintMinutes, breakMinutes: settings.s.breakMinutes)
        timer.startSprint()
        let target = pendingTarget ?? index
        pendingTarget = nil
        activity()
        if target >= chunks.count { finish() } else { go(to: target) }
    }

    func keepGoing(minutes: Int) {
        timer.extendSprint(minutes: minutes)
        showToast("+\(minutes) min. Nice.")
    }

    // MARK: - Drift and nudges

    func zonedOut() {
        guard phase == .reading, !timer.isOnBreak, !showCheckpoint else { return }
        activity()
        driftCount += 1
        sprintDrifts += 1
        go(to: max(index - 1, 0))
        if sprintDrifts >= 3 {
            suggestBreak = true
            showToast("A few drifts in a row. Your brain might want a break.", seconds: 5)
        } else {
            let lines = [
                "No problem. Back one step.",
                "Noticing is the skill. Let's re-read this bit.",
                "It happens. Back one step, nice and slow.",
            ]
            showToast(lines.randomElement() ?? lines[0])
        }
    }

    private func activity() {
        lastActivity = Date()
        if nudge { nudge = false }
    }

    private func startHeartbeat() {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.checkIdle()
            }
        }
    }

    /// A gentle "still with me?" when you've been on one chunk far longer than your pace suggests.
    private func checkIdle() {
        guard settings.s.nudges, phase == .reading, !showCheckpoint, !timer.isOnBreak, !readAloud,
              NSApp.isActive, !nudge, let chunk = currentChunk else { return }
        let expected = Double(chunk.wordCount) / max(wordsPerMinute, 60) * 60
        let limit = max(45, expected * 4)
        if Date().timeIntervalSince(lastActivity) > limit {
            nudge = true
        }
    }

    private func observeAppActivity() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appWentAway() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appCameBack() }
        })
    }

    private func appWentAway() {
        awaySince = Date()
        if !readAloud { timer.autoPaused = true }
    }

    private func appCameBack() {
        timer.autoPaused = false
        if let since = awaySince, Date().timeIntervalSince(since) > 8, phase == .reading, !timer.isOnBreak {
            showToast("Welcome back. You were here.", seconds: 4)
            chunkEnteredAt = Date()
        }
        awaySince = nil
        activity()
    }

    // MARK: - Read aloud

    func toggleReadAloud() {
        readAloud.toggle()
        activity()
        if readAloud {
            if phase == .reading && !timer.isOnBreak { speakCurrent() }
        } else {
            speaker.stop()
        }
    }

    private func speakCurrent() {
        guard phase == .reading, let chunk = currentChunk else { return }
        let voice = Speaker.voice(id: settings.s.voiceID, language: language)
        speaker.speak(chunk: chunk, rate: Float(settings.s.speechRate), voice: voice)
    }

    private func speechFinishedChunk() {
        guard readAloud, settings.s.autoAdvance, phase == .reading, !showCheckpoint, !timer.isOnBreak else { return }
        // The voice has read the whole bite, including any part below the fold.
        advance()
    }

    // MARK: - Pace

    private func measurePace() {
        guard !readAloud, let chunk = currentChunk, chunk.wordCount >= 6 else { return }
        let seconds = Date().timeIntervalSince(chunkEnteredAt)
        guard seconds > 1, seconds < 180 else { return }
        let wpm = Double(chunk.wordCount) / seconds * 60
        guard wpm > 40, wpm < 900 else { return }
        wordsPerMinute = wordsPerMinute * 0.85 + wpm * 0.15
    }

    // MARK: - Chunking

    func rechunk() {
        let offset = currentChunk?.wordOffset ?? 0
        apply(Chunker.run(blocks, size: settings.s.chunkSize), keepingWordOffset: offset)
    }

    private func apply(_ output: Chunker.Output, keepingWordOffset offset: Int) {
        chunks = output.chunks
        sections = output.sections
        totalWords = output.totalWords
        index = chunks.lastIndex { $0.wordOffset <= offset } ?? 0
        chunkHeights.removeAll()
        page = 0
        pageCount = 1
        // Don't resume on the very last chunk of a finished document.
        if index == chunks.count - 1 && offset >= totalWords && chunks.count > 1 { index = 0 }
        furthest = index
    }

    // MARK: - Persistence

    private func persist() {
        guard let key = docKey, let chunk = currentChunk else { return }
        let focus = timer.focusedSeconds - recordedFocus
        let sprints = timer.completedSprints - recordedSprints
        recordedFocus = timer.focusedSeconds
        recordedSprints = timer.completedSprints
        let total = totalWords
        let wpm = wordsPerMinute
        let finished = phase == .finished && index == chunks.count - 1
        store.update(key, title: title) { record in
            record.title = self.title
            record.wordOffset = finished ? total : chunk.wordOffset
            record.totalWords = total
            record.lastOpened = Date()
            record.focusSeconds += focus
            record.sprints += sprints
            record.wpm = wpm
        }
    }

    // MARK: - Keyboard

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handleKey(event) } ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window = event.window, window === self.window, window.attachedSheet == nil else { return false }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        if window.firstResponder is NSTextView { return false }

        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 49: // space
            if shift { previous() } else { primaryAction() }
            NSCursor.setHiddenUntilMouseMoves(true)
            return true
        case 36, 76: // return, enter
            primaryAction()
            return true
        case 124, 125: // right, down
            next()
            NSCursor.setHiddenUntilMouseMoves(true)
            return true
        case 123, 126: // left, up
            previous()
            NSCursor.setHiddenUntilMouseMoves(true)
            return true
        case 53: // escape
            if zen { zen = false; return true }
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil); return true }
            return false
        default:
            break
        }

        guard phase == .reading else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() ?? "" {
        case "j": next()
        case "k": previous()
        case "d": zonedOut()
        case "r": toggleReadAloud()
        case "f": window.toggleFullScreen(nil)
        case "z": zen.toggle()
        case "o": showOutline.toggle()
        case "n": showNotes.toggle()
        case "t": timer.togglePause()
        case "b": takeBreakNow()
        default: return false
        }
        return true
    }

    // MARK: - Misc

    func showToast(_ text: String, seconds: Double = 3.5) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation { self?.toast = nil }
        }
    }

    func close() {
        persist()
        heartbeat?.cancel()
        toastTask?.cancel()
        speaker.stop()
        timer.stop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        store.saveNow()
    }
}
