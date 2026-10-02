import AppKit
import SwiftUI

@main
struct AnchorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppState()

    init() {
        // `Anchor --dump <file> [chunk-size]` prints how a document gets chunked, for debugging parsers.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--dump"), i + 1 < args.count {
            DebugDump.run(path: args[i + 1], size: args.count > i + 2 ? ChunkSize(rawValue: args[i + 2]) ?? .small : .small)
            exit(0)
        }
    }

    var body: some Scene {
        Window("Anchor", id: "main") {
            RootView()
                .environment(app)
                .onAppear {
                    delegate.onTerminate = { app.shutdown() }
                    delegate.attach { url in app.open(url) }
                    DebugScript.runIfRequested(app: app)
                }
        }
        .defaultSize(width: 1040, height: 780)
        .commands { AnchorCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?
    private var handler: ((URL) -> Void)?
    private var pending: [URL] = []

    func attach(_ handler: @escaping (URL) -> Void) {
        self.handler = handler
        pending.forEach(handler)
        pending.removeAll()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let handler { handler(url) } else { pending.append(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }
}

struct AnchorCommands: Commands {
    let app: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { app.showOpenPanel() }
                .keyboardShortcut("o")
            Button("Open the Guided Tour") { app.openTour() }
            Divider()
            Button("Close Document") { app.closeDocument() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
        CommandMenu("Reading") {
            Button("Larger Text") { app.settings.biggerText() }
                .keyboardShortcut("=")
            Button("Smaller Text") { app.settings.smallerText() }
                .keyboardShortcut("-")
            Button("Default Text Size") { app.settings.s.fontSize = ReaderSettings.defaultFontSize }
                .keyboardShortcut("0")
            Divider()
            Button("Take a Break Now") { app.reader?.takeBreakNow() }
            Button("End Session") { app.reader?.finish() }
            Divider()
            Button("Export Recall Notes…") { app.reader?.exportNotes() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Reading Comfort Setup…") { app.showComfortSetup = true }
        }
        CommandGroup(replacing: .help) {
            Button("Why These Features Work") { app.showResearch = true }
            Button("Keyboard Shortcuts") { app.showShortcuts = true }
                .keyboardShortcut("/", modifiers: [.command])
        }
    }
}
