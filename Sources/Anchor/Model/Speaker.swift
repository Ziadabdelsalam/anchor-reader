import AVFoundation

/// Reads the current chunk aloud and reports which word is being spoken,
/// so it can be highlighted (reading while listening).
@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    struct Highlight: Equatable {
        let segmentID: Int
        let range: NSRange
        /// For tables, the row being read (the whole row is highlighted).
        var row: Int?
    }

    private(set) var highlight: Highlight?
    private(set) var isSpeaking = false
    var onFinishedChunk: (() -> Void)?

    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var segmentFor: [ObjectIdentifier: (segment: Int, row: Int?)] = [:]
    @ObservationIgnored private var queued: [AVSpeechUtterance] = []
    @ObservationIgnored private var lastUtterance: ObjectIdentifier?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(chunk: Chunk, rate: Float, voice: AVSpeechSynthesisVoice?) {
        stop()
        var last: AVSpeechUtterance?
        func enqueue(_ text: String, segment: Int, row: Int? = nil) {
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = rate
            utterance.voice = voice
            utterance.postUtteranceDelay = 0.12
            if ProcessInfo.processInfo.environment["ANCHOR_MUTE"] != nil { utterance.volume = 0 }
            segmentFor[ObjectIdentifier(utterance)] = (segment, row)
            queued.append(utterance)
            synth.speak(utterance)
            last = utterance
        }
        for segment in chunk.segments {
            if let table = segment.table {
                // Tables are read row by row ("Name: Ada. Role: Engineer."), highlighting each row.
                for r in table.rows.indices {
                    let spoken = table.spokenRow(r)
                    if !spoken.isEmpty { enqueue(spoken, segment: segment.id, row: r) }
                }
            } else if segment.kind.isCode {
                enqueue("Code example.", segment: -1)
            } else {
                enqueue(segment.plain, segment: segment.id)
            }
        }
        lastUtterance = last.map(ObjectIdentifier.init)
        isSpeaking = last != nil
        if last == nil { onFinishedChunk?() }
    }

    func stop() {
        segmentFor.removeAll()
        queued.removeAll()
        lastUtterance = nil
        highlight = nil
        isSpeaking = false
        if synth.isSpeaking || synth.isPaused {
            synth.stopSpeaking(at: .immediate)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.willSpeak(key, characterRange) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(key) }
    }

    private func willSpeak(_ key: ObjectIdentifier, _ range: NSRange) {
        guard let target = segmentFor[key] else { return }
        highlight = target.segment >= 0 ? Highlight(segmentID: target.segment, range: range, row: target.row) : nil
    }

    private func finished(_ key: ObjectIdentifier) {
        guard segmentFor[key] != nil else { return }
        segmentFor[key] = nil
        if key == lastUtterance {
            highlight = nil
            isSpeaking = false
            lastUtterance = nil
            queued.removeAll()
            onFinishedChunk?()
        }
    }

    // MARK: - Voices

    static func voices(for language: String?) -> [AVSpeechSynthesisVoice] {
        let lang = language ?? Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(lang) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    static func voice(id: String?, language: String?) -> AVSpeechSynthesisVoice? {
        if let id, let voice = AVSpeechSynthesisVoice(identifier: id) { return voice }
        return voices(for: language).first ?? AVSpeechSynthesisVoice(language: nil)
    }
}
