import AppKit
import SwiftUI

/// Developer-only automation: `ANCHOR_SCRIPT=/path/to/script.txt` runs one command per line
/// (open <file>, tour, start, next [n], prev, drift, break, skipbreak, resume, checkpoint <text>,
/// set <key> <value>, wait <seconds>, snap <file.png>, quit). Used to test the UI end to end.
enum DebugScript {
    private static var retained: [NSWindow] = []

    static func runIfRequested(app: AppState) {
        guard let path = ProcessInfo.processInfo.environment["ANCHOR_SCRIPT"],
              let script = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            for line in lines {
                await execute(line, app: app)
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
    }

    private static func execute(_ line: String, app: AppState) async {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        let reader = app.reader
        switch parts[0] {
        case "open": app.open(URL(fileURLWithPath: arg))
        case "drop":
            // Runs a dropped file through the same path as a real Finder drag.
            let provider = NSItemProvider(object: URL(fileURLWithPath: arg) as NSURL)
            print("drop accepted: \(app.handleDrop([provider]))")
            fflush(stdout)
        case "dragover": app.isDropTargeted = arg != "off"
        case "tour": app.openTour()
        case "comfort": app.showComfortSetup = arg != "off"
        case "research": app.showResearch = arg != "off"
        case "start": reader?.startSession()
        case "next": for _ in 0..<(Int(arg) ?? 1) { reader?.primaryAction() }
        case "prev": reader?.previous()
        case "jump": reader?.jump(to: Int(arg) ?? 0)
        case "drift": reader?.zonedOut()
        case "break": reader?.takeBreakNow()
        case "skipbreak": reader?.timer.skipBreak()
        case "resume": reader?.resumeAfterBreak()
        case "finish": reader?.finish()
        case "expire": reader?.timer.expireSoon()
        case "viewcode":
            if let chunk = reader?.currentChunk, let segment = chunk.segments.first(where: { $0.kind.isCode }) {
                app.codeViewer = CodeViewerItem(text: segment.plain)
            }
        case "fonttest":
            let window = NSWindow(contentViewController: NSHostingController(rootView: ComfortSetupView(startAt: .trial(0)).environment(app)))
            window.title = "Font test"
            window.makeKeyAndOrderFront(nil)
            retained.append(window)
        case "keyto":
            // keyto <window title> <keyCode> <chars>
            let kv = arg.split(separator: " ").map(String.init)
            guard kv.count >= 3, let window = NSApp.windows.first(where: { $0.title == kv[0].replacingOccurrences(of: "_", with: " ") }), let code = UInt16(kv[1]) else { break }
            let chars = kv[2].replacingOccurrences(of: "SPACE", with: " ")
            window.makeKey()
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: chars,
                                            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                NSApp.postEvent(event, atStart: false)
            }
        case "outline": reader?.showOutline.toggle()
        case "notes": reader?.showNotes.toggle()
        case "aloud": reader?.toggleReadAloud()
        case "checkpoint": reader?.completeCheckpoint(note: arg.isEmpty ? nil : arg)
        case "close": app.closeDocument()
        case "set":
            let kv = arg.split(separator: " ").map(String.init)
            guard kv.count == 2 else { break }
            switch kv[0] {
            case "fontSize": app.settings.s.fontSize = Double(kv[1]) ?? 24
            case "theme": app.settings.s.theme = ThemeID(rawValue: kv[1]) ?? .paper
            case "chunk": app.settings.s.chunkSize = ChunkSize(rawValue: kv[1]) ?? .small
            case "font": app.settings.s.fontID = kv[1]
            case "dim": app.settings.s.dimLevel = Double(kv[1]) ?? 0.2
            default: break
            }
        case "wait": try? await Task.sleep(for: .seconds(Double(arg) ?? 1))
        case "snap": snapshotAll(prefix: arg)
        case "settings":
            let tab = Int(arg) ?? 0
            let views: [AnyView] = [
                AnyView(VStack(spacing: 0) { TypographyControls(); InterfaceSizeRow() }),
                AnyView(FocusSettings()), AnyView(VoiceSettings()),
            ]
            let window = NSWindow(contentViewController: NSHostingController(rootView: views[min(tab, 2)].environment(app).frame(width: 620, height: 720)))
            window.title = "Settings"
            window.makeKeyAndOrderFront(nil)
            retained.append(window)
        case "key":
            // key <keyCode> <characters> [shift]: posts a real key event through the event queue.
            let kv = arg.split(separator: " ").map(String.init)
            guard let code = UInt16(kv.first ?? ""), let window = reader?.window ?? NSApp.mainWindow else { break }
            let chars = kv.count > 1 ? kv[1].replacingOccurrences(of: "SPACE", with: " ") : ""
            let flags: NSEvent.ModifierFlags = kv.contains("shift") ? [.shift] : []
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: chars,
                                            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                NSApp.postEvent(event, atStart: false)
            }
        case "state":
            if let r = reader { print("STATE index=\(r.index) phase=\(r.phase) drift=\(r.driftCount) zen=\(r.zen) outline=\(r.showOutline) aloud=\(r.readAloud) checkpoint=\(r.showCheckpoint) timer=\(r.timer.phase) page=\(r.page + 1)/\(r.pageCount)"); fflush(stdout) }
        case "quit": NSApp.terminate(nil)
        default: print("DebugScript: unknown command \(line)")
        }
    }

    /// Renders every visible window of this app to PNG (no screen-recording permission needed).
    private static func snapshotAll(prefix: String) {
        for (i, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.width > 100 {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = URL(fileURLWithPath: i == 0 ? prefix : prefix.replacingOccurrences(of: ".png", with: "-w\(i).png"))
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("snap \(url.path) \(Int(window.frame.width))x\(Int(window.frame.height)) \(window.title)")
            fflush(stdout)
        }
    }
}
