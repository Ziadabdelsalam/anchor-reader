import Foundation

/// Short focus sprints with scheduled breaks.
/// When a sprint ends, the break waits for you to finish the chunk you're on.
@Observable
final class SprintTimer {
    enum Phase: Equatable {
        case idle
        case sprint
        /// Time is up; the break starts at the next chunk boundary.
        case sprintDone
        case onBreak
        case breakDone
    }

    private(set) var phase: Phase = .idle
    private(set) var remaining: TimeInterval = 0
    private(set) var completedSprints = 0
    private(set) var focusedSeconds: TimeInterval = 0
    var userPaused = false
    /// Paused automatically while the app is in the background.
    var autoPaused = false

    var sprintLength: TimeInterval = 5 * 60
    var breakLength: TimeInterval = 60

    var onSprintEnded: (() -> Void)?
    var onBreakEnded: (() -> Void)?

    @ObservationIgnored private var task: Task<Void, Never>?

    var isOnBreak: Bool { phase == .onBreak || phase == .breakDone }
    var isPaused: Bool { userPaused || autoPaused }

    func configure(sprintMinutes: Int, breakMinutes: Int) {
        sprintLength = TimeInterval(max(1, sprintMinutes) * 60)
        breakLength = TimeInterval(max(1, breakMinutes) * 60)
    }

    func startSprint() {
        phase = .sprint
        remaining = sprintLength
        userPaused = false
        ensureTicking()
    }

    func extendSprint(minutes: Int) {
        phase = .sprint
        remaining += TimeInterval(minutes * 60)
        ensureTicking()
    }

    func startBreak() {
        phase = .onBreak
        remaining = breakLength
        userPaused = false
        ensureTicking()
    }

    func skipBreak() {
        guard phase == .onBreak else { return }
        phase = .breakDone
        remaining = 0
    }

    func stop() {
        phase = .idle
        remaining = 0
        task?.cancel()
        task = nil
    }

    func togglePause() { userPaused.toggle() }

    /// Testing aid: end the current sprint or break in a second.
    func expireSoon() {
        if phase == .sprint || phase == .onBreak { remaining = 1 }
    }

    private func ensureTicking() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        switch phase {
        case .sprint:
            guard !isPaused else { return }
            remaining -= 1
            focusedSeconds += 1
            if remaining <= 0 {
                remaining = 0
                phase = .sprintDone
                completedSprints += 1
                onSprintEnded?()
            }
        case .sprintDone:
            if !isPaused { focusedSeconds += 1 }
        case .onBreak:
            // Breaks keep counting while you're away from the screen; that's the point.
            guard !userPaused else { return }
            remaining -= 1
            if remaining <= 0 {
                remaining = 0
                phase = .breakDone
                onBreakEnded?()
            }
        case .idle, .breakDone:
            break
        }
    }
}

extension TimeInterval {
    var mmss: String {
        let total = Int(self.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
