import Foundation

nonisolated struct Note: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date = Date()
    var section: String
    var text: String
}

nonisolated struct DocRecord: Codable, Identifiable, Sendable {
    var id: String { path }
    var path: String
    var title: String
    var wordOffset = 0
    var totalWords = 0
    var lastOpened = Date()
    var notes: [Note] = []
    var focusSeconds: Double = 0
    var sprints = 0
    var wpm: Double?

    var progress: Double {
        totalWords == 0 ? 0 : min(1, Double(wordOffset) / Double(totalWords))
    }
}

/// Remembers where you stopped in each document, your recall notes, and your pace.
/// Stored as JSON in ~/Library/Application Support/Anchor.
@Observable
final class ProgressStore {
    private(set) var records: [String: DocRecord] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Anchor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: DocRecord].self, from: data) {
            records = decoded
        }
    }

    var recents: [DocRecord] {
        records.values.sorted { $0.lastOpened > $1.lastOpened }
    }

    func record(_ key: String) -> DocRecord? { records[key] }

    func update(_ key: String, title: String, _ change: (inout DocRecord) -> Void) {
        var record = records[key] ?? DocRecord(path: key, title: title)
        change(&record)
        records[key] = record
        scheduleSave()
    }

    func remove(_ key: String) {
        records[key] = nil
        scheduleSave()
    }

    func saveNow() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
