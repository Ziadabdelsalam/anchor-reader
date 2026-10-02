import AVFoundation
import SwiftUI

struct SettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // No `step:` so macOS doesn't draw a row of tick marks; values are rounded instead.
            Slider(value: Binding(
                get: { value },
                set: { value = min(max(($0 / step).rounded() * step, range.lowerBound), range.upperBound) }
            ), in: range)
            if let hint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ThemePicker: View {
    @Binding var selection: ThemeID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(ThemeID.allCases) { id in
                    let palette = id.palette
                    Button {
                        selection = id
                    } label: {
                        Text("Aa")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(palette.background))
                            .overlay(Circle().strokeBorder(selection == id ? palette.accent : Color.secondary.opacity(0.3), lineWidth: selection == id ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(id.label)
                }
            }
            Text(selection.label + (selection == .blue || selection == .green || selection == .rose ? ". Tints are a comfort preference; studies haven't found that colored overlays improve reading." : ""))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Text size, font, spacing and colors. Used in the toolbar popover and in Settings.
struct TypographyControls: View {
    @Environment(AppState.self) private var app
    var compact = false

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("Text") {
                Picker("Font", selection: $settings.s.fontID) {
                    ForEach(FontOption.available) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                SettingSlider(title: "Size", value: $settings.s.fontSize,
                              range: ReaderSettings.minFontSize...ReaderSettings.maxFontSize, step: 1,
                              format: { "\(Int($0)) pt" },
                              hint: compact ? nil : "Bigger text was read faster in eye-tracking studies, by readers with and without dyslexia. Never go below what feels effortless.")
                SettingSlider(title: "Letter spacing", value: $settings.s.letterSpacing, range: 0...4, step: 0.1,
                              format: { String(format: "+%.1f", $0) },
                              hint: compact ? nil : "Extra space between letters reduces 'crowding', when letters seem to blur into each other.")
                SettingSlider(title: "Word spacing", value: $settings.s.wordSpacing, range: 0...16, step: 1,
                              format: { "+\(Int($0))" })
                SettingSlider(title: "Line height", value: $settings.s.lineHeight, range: 1.2...2.6, step: 0.1,
                              format: { String(format: "%.1f×", $0) })
                SettingSlider(title: "Line width", value: $settings.s.lineLength, range: 30...100, step: 1,
                              format: { "\(Int($0)) characters" },
                              hint: compact ? nil : "Most people find 45 to 72 characters per line most comfortable.")
            }

            Section("Colors") {
                ThemePicker(selection: $settings.s.theme)
            }

            Section("Focus") {
                SettingSlider(title: "Surrounding text", value: $settings.s.dimLevel, range: 0.05...1, step: 0.05,
                              format: { $0 >= 0.99 ? "Not dimmed" : "\(Int($0 * 100))% visible" },
                              hint: compact ? nil : "How much the text around the current bit fades. Lower means fewer lines competing for your eyes.")
                Toggle("Highlight the current bit", isOn: $settings.s.spotlight)
                Picker("Bite size", selection: $settings.s.chunkSize) {
                    ForEach(ChunkSize.allCases) { Text($0.label).tag($0) }
                }
            }

            if !compact {
                Section("Preview") {
                    PreviewText(settings: settings.s)
                }
            }
        }
        .formStyle(.grouped)
        .font(.system(size: compact ? 14 : 15))
    }
}

struct PreviewText: View {
    let settings: ReaderSettings

    var body: some View {
        let style = TextStyle(settings)
        let segment = Segment(
            id: -1,
            kind: .paragraph,
            text: AttributedString("Reading one small piece at a time keeps the page from blurring together. Each bit gets your full attention before you move on."),
            wordCount: 22
        )
        Text(style.styled(segment, highlight: nil))
            .font(style.body)
            .lineSpacing(style.lineExtra)
            .foregroundStyle(style.theme.text)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(style.theme.background))
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            Tab("Reading", systemImage: "textformat.size") {
                VStack(spacing: 0) {
                    TypographyControls()
                    InterfaceSizeRow()
                }
            }
            Tab("Focus", systemImage: "timer") {
                FocusSettings()
            }
            Tab("Voice", systemImage: "speaker.wave.2") {
                VoiceSettings()
            }
            Tab("Research", systemImage: "books.vertical") {
                ResearchView(asSheet: false)
            }
        }
        .frame(width: 620, height: 720)
    }
}

struct InterfaceSizeRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("Buttons, menus and notes") {
                SettingSlider(title: "Interface text size", value: $settings.s.interfaceSize, range: 13...24, step: 1,
                              format: { "\(Int($0)) pt" })
                Button("Run the reading comfort setup again…") { app.showComfortSetup = true }
            }
        }
        .formStyle(.grouped)
        .frame(height: 170)
        .font(.system(size: 15))
    }
}

struct FocusSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("Sprints") {
                Picker("Sprint length", selection: $settings.s.sprintMinutes) {
                    ForEach([3, 5, 7, 10, 15, 20, 25], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Break length", selection: $settings.s.breakMinutes) {
                    ForEach([1, 2, 3, 5, 10], id: \.self) { Text($0 == 1 ? "1 minute" : "\($0) minutes").tag($0) }
                }
                Text("When a sprint ends, Anchor lets you finish the bit you're on, then starts the break. Scheduled breaks keep sessions from stretching until you're drained.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Play a soft sound when a sprint or break ends", isOn: $settings.s.sounds)
            }
            Section("Recall checkpoints") {
                Picker("Ask me to sum up", selection: $settings.s.checkpoints) {
                    ForEach(CheckpointMode.allCases) { Text($0.label).tag($0) }
                }
                Text("Short recall questions between sections cut mind-wandering roughly in half in a Harvard study, and improved what people remembered.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Nudges") {
                Toggle("Gently ask “still with me?” when I've stalled on one bit", isOn: $settings.s.nudges)
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 15))
    }
}

struct VoiceSettings: View {
    @Environment(AppState.self) private var app
    @State private var synth = AVSpeechSynthesizer()

    var body: some View {
        @Bindable var settings = app.settings
        let voices = Speaker.voices(for: app.reader?.language)
        Form {
            Section("Read aloud") {
                Picker("Voice", selection: Binding(
                    get: { settings.s.voiceID ?? voices.first?.identifier ?? "" },
                    set: { settings.s.voiceID = $0 }
                )) {
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name)\(qualityLabel(voice))").tag(voice.identifier)
                    }
                }
                SettingSlider(title: "Speed", value: $settings.s.speechRate, range: 0.3...0.65, step: 0.01,
                              format: { rate in rate < 0.42 ? "Slow" : (rate < 0.52 ? "Natural" : "Fast") })
                Toggle("Move to the next bit automatically", isOn: $settings.s.autoAdvance)
                Button("Test voice") {
                    synth.stopSpeaking(at: .immediate)
                    let utterance = AVSpeechUtterance(string: "This is how reading aloud will sound. Each word lights up as it's spoken.")
                    utterance.voice = Speaker.voice(id: settings.s.voiceID, language: app.reader?.language)
                    utterance.rate = Float(settings.s.speechRate)
                    synth.speak(utterance)
                }
                Text("Listening while you follow the highlighted words improved comprehension for students with ADHD-related reading difficulties. Better voices: System Settings → Accessibility → Spoken Content → System Voice → Manage Voices, then download an “Enhanced” or “Premium” voice.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 15))
    }

    private func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: " (Premium)"
        case .enhanced: " (Enhanced)"
        default: ""
        }
    }
}

// MARK: - Comfort setup

/// Step 1: pick a size that feels effortless. Step 2: a short timed reading in a few
/// fonts to find the one *you* read fastest in (no single font is best for everyone).
struct ComfortSetupView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    enum Step: Equatable { case size, fontIntro, trial(Int), results }

    @State private var step: Step
    @State private var order: [FontOption]
    @State private var startedAt = Date()
    @State private var results: [(FontOption, Double)] = []
    /// Done is held back briefly so a double-tap can't skip a passage and skew the timing.
    @State private var canFinish = false

    init(startAt: Step = .size) {
        _step = State(initialValue: startAt)
        _order = State(initialValue: FontOption.finderCandidates.shuffled())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch step {
            case .size: sizeStep
            case .fontIntro: fontIntro
            case .trial(let i): trial(i)
            case .results: resultsStep
            }
        }
        .frame(width: 760, height: 680)
        .background(app.settings.theme.background)
        .foregroundStyle(app.settings.theme.text)
        .preferredColorScheme(app.settings.theme.isDark ? .dark : .light)
        .onDisappear { app.settings.s.comfortSetupDone = true }
    }

    // Step 1

    private var sizeStep: some View {
        @Bindable var settings = app.settings
        let theme = settings.theme
        let sizes: [Double] = [18, 21, 24, 28, 32, 38]
        return VStack(alignment: .leading, spacing: 16) {
            header(step: "Step 1 of 2", title: "Which size feels effortless?",
                   subtitle: "Click the smallest one you can read without any strain. Not the smallest you *can* read; the one that feels easy.")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sizes, id: \.self) { size in
                        Button {
                            settings.s.fontSize = size
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text("\(Int(size))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(theme.secondary)
                                    .frame(width: 26, alignment: .trailing)
                                Text("Each bit gets your full attention.")
                                    .font(settings.font.font(size: size))
                                    .kerning(settings.s.letterSpacing)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                Spacer()
                                if Int(settings.s.fontSize) == Int(size) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Int(settings.s.fontSize) == Int(size) ? theme.highlight : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            SettingSlider(title: "Fine-tune", value: $settings.s.fontSize,
                          range: ReaderSettings.minFontSize...ReaderSettings.maxFontSize, step: 1,
                          format: { "\(Int($0)) pt" })
            SettingSlider(title: "Letter spacing", value: $settings.s.letterSpacing, range: 0...4, step: 0.1,
                          format: { String(format: "+%.1f", $0) },
                          hint: "If letters seem to run together, add a little space.")
            HStack {
                Button("Skip for now") { finish() }
                Spacer()
                Button("Next: find my font") { step = .fontIntro }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(32)
        .font(.system(size: 15))
    }

    // Step 2

    private var fontIntro: some View {
        let theme = app.settings.theme
        return VStack(alignment: .leading, spacing: 18) {
            header(step: "Step 2 of 2", title: "Find the font you read fastest in",
                   subtitle: "In a study of 352 readers, the gap between a person's fastest and slowest font was 35%, with no loss of understanding. And the fastest font was different for different people.")
            VStack(alignment: .leading, spacing: 10) {
                Label("You'll read \(FontOption.finderCandidates.count) short passages, about 30 seconds each.", systemImage: "text.alignleft")
                Label("Read normally, the way you'd read something you need to understand.", systemImage: "eye")
                Label("Press Space (or click Done) as soon as you finish each one.", systemImage: "space")
            }
            .font(.system(size: 16))
            Spacer()
            HStack {
                Button("Back") { step = .size }
                Button("Skip") { finish() }
                Spacer()
                Button("Start") {
                    order = FontOption.finderCandidates.shuffled()
                    results = []
                    startedAt = Date()
                    step = .trial(0)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(32)
        .font(.system(size: 15))
    }

    private func trial(_ i: Int) -> some View {
        let settings = app.settings.s
        let font = order[i]
        let passage = FontPassages.all[i % FontPassages.all.count]
        var trialSettings = settings
        trialSettings.fontID = font.id
        let style = TextStyle(trialSettings)
        let segment = Segment(id: -1, kind: .paragraph, text: AttributedString(passage), wordCount: countWords(passage))

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Passage \(i + 1) of \(order.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(style.theme.secondary)
                Spacer()
                ProgressView(value: Double(i), total: Double(order.count))
                    .frame(width: 160)
            }
            ScrollView {
                Text(style.styled(segment, highlight: nil))
                    .font(style.body)
                    .lineSpacing(style.lineExtra)
                    .foregroundStyle(style.theme.text)
                    .frame(maxWidth: min(style.columnWidth, 680), alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Text("Font name hidden so it doesn't sway you.")
                    .font(.system(size: 13))
                    .foregroundStyle(style.theme.secondary)
                Spacer()
                Button("Done") { recordTrial(i, words: segment.wordCount) }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!canFinish)
                    .buttonStyle(.borderedProminent)
                    .tint(style.theme.accent)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .id(i)
        .onAppear {
            startedAt = Date()
            canFinish = false
        }
        .task(id: i) {
            try? await Task.sleep(for: .seconds(2.5))
            canFinish = true
        }
    }

    private func recordTrial(_ i: Int, words: Int) {
        let seconds = max(Date().timeIntervalSince(startedAt), 1)
        results.append((order[i], Double(words) / seconds * 60))
        if i + 1 < order.count {
            step = .trial(i + 1)
        } else {
            results.sort { $0.1 > $1.1 }
            var map: [String: Double] = [:]
            for (font, wpm) in results { map[font.id] = wpm }
            app.settings.s.fontFinderResults = map
            step = .results
        }
    }

    private var resultsStep: some View {
        @Bindable var settings = app.settings
        let theme = settings.theme
        let top = results.first?.1 ?? 1
        return VStack(alignment: .leading, spacing: 16) {
            header(step: "Results", title: results.first.map { "You read fastest in \($0.0.name)" } ?? "Results",
                   subtitle: "Pick whichever feels best. Speed is one signal; comfort matters too. You can run this again any time from the Reading menu.")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(results.enumerated()), id: \.offset) { rank, item in
                        let (font, wpm) = item
                        Button {
                            settings.s.fontID = font.id
                        } label: {
                            HStack(spacing: 14) {
                                Text(font.name)
                                    .font(font.font(size: 22))
                                    .frame(width: 270, alignment: .leading)
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(rank == 0 ? theme.accent : theme.secondary.opacity(0.35))
                                        .frame(width: max(8, geo.size.width * wpm / top))
                                }
                                .frame(height: 10)
                                Text("\(Int(wpm)) wpm")
                                    .monospacedDigit()
                                    .frame(width: 80, alignment: .trailing)
                                Image(systemName: settings.s.fontID == font.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(settings.s.fontID == font.id ? theme.accent : theme.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(settings.s.fontID == font.id ? theme.highlight : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Tip: a single run is a rough guide, since passages differ a little. If two fonts are close, run it again or go with the one that feels calmer.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondary)
            HStack {
                Button("Run again") { step = .fontIntro }
                Spacer()
                Button("Done") { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(32)
        .font(.system(size: 15))
        .onAppear {
            if let best = results.first { settings.s.fontID = best.0.id }
        }
    }

    private func header(step: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(app.settings.theme.accent)
            Text(title)
                .font(.system(size: 26, weight: .bold))
            Text(.init(subtitle))
                .font(.system(size: 15))
                .foregroundStyle(app.settings.theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finish() {
        app.settings.s.comfortSetupDone = true
        dismiss()
    }
}
