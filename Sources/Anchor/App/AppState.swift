import AppKit
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    let settings = SettingsStore()
    let store = ProgressStore()
    var reader: ReaderModel?
    var isLoading = false
    var errorMessage: String?
    var showComfortSetup = false
    var showResearch = false
    var showShortcuts = false
    /// True while a file is being dragged over the window.
    var isDropTargeted = false
    /// A code block or diagram open at full size.
    var codeViewer: CodeViewerItem?

    func open(_ url: URL) {
        Task { await load(url) }
    }

    private func load(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let document = try await DocumentLoader.load(url)
            let output = await chunk(document)
            guard !output.chunks.isEmpty else { throw LoadError.noText }
            reader?.close()
            reader = ReaderModel(document: document, key: url.path, initial: output, settings: settings, store: store)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openTour() {
        let document = LoadedDocument(title: "Welcome to Anchor", blocks: MarkdownParser.parse(SampleDocument.markdown), language: "en")
        let output = Chunker.run(document.blocks, size: settings.s.chunkSize)
        reader?.close()
        reader = ReaderModel(document: document, key: nil, initial: output, settings: settings, store: store)
    }

    private func chunk(_ document: LoadedDocument) async -> Chunker.Output {
        let blocks = document.blocks
        let size = settings.s.chunkSize
        return await Task.detached(priority: .userInitiated) { Chunker.run(blocks, size: size) }.value
    }

    /// Handles files dragged in from Finder (or anywhere that provides a file URL).
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in self.openDropped(url) }
        }
        return true
    }

    private func openDropped(_ url: URL) {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
            errorMessage = "That file couldn't be found."
            return
        }
        if isFolder.boolValue {
            errorMessage = "That's a folder. Drop a single document instead."
            return
        }
        open(url)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentLoader.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a document to read"
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func closeDocument() {
        reader?.close()
        reader = nil
    }

    func shutdown() {
        reader?.close()
        store.saveNow()
    }
}
