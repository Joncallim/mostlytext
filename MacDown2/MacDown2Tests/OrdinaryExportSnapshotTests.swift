import AppKit
import AppSettings
import ExportService
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes
@testable import Workspace

@MainActor
@Suite("Ordinary export snapshot")
struct OrdinaryExportSnapshotTests {
    @Test func laterSettingsChangesDoNotAlterAnExportAlreadyInProgress() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let source = "@Note {\nbody\n}\n"
        let document = FileDocument(fileURL: fixture.directory.appendingPathComponent("source.md"), text: source)
        let snapshot = OrdinaryExportSnapshot(
            document: document,
            theme: fixture.themeController.current,
            parseOptions: DocumentEditorSplitView.markdownParseOptions(from: fixture.settings.markdown)
        )
        let parser = GatedExportParseExecutor()
        let operation = Task { @MainActor in
            try await fixture.exporter.performExport(
                snapshot: snapshot,
                selection: .init(url: fixture.outputURL, format: .standaloneHTML, style: .embedded),
                engine: parser
            )
        }

        await parser.waitForFirstCall()
        fixture.themeController.setAppearance(.dark)
        fixture.settings.markdown = MarkdownSettings(parsesBlockDirectives: true)
        await parser.releaseFirstCall()

        let result = try await operation.value
        let html = try String(contentsOf: result.primaryFile, encoding: .utf8)
        let calls = await parser.callsSnapshot()
        #expect(fixture.themeController.current == BundledThemes.dark)
        #expect(fixture.settings.markdown.parsesBlockDirectives)
        #expect(calls.count == 1)
        #expect(calls.allSatisfy { $0.text == source })
        #expect(calls.allSatisfy { $0.options == .default })
        #expect(calls.allSatisfy { $0.revision == Int(document.mutationGeneration) })
        #expect(html.contains(ExportThemeStylesheet.variables(for: BundledThemes.light)))
        #expect(!html.contains(ExportThemeStylesheet.variables(for: BundledThemes.dark)))
    }

    @Test func aDestinationCreatedWhileTheContributionParseIsHeldIsPreserved() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let snapshot = OrdinaryExportSnapshot(
            document: FileDocument(fileURL: fixture.directory.appendingPathComponent("source.md"), text: "# Source"),
            theme: BundledThemes.light, parseOptions: .default
        )
        let parser = GatedExportParseExecutor()
        let operation = Task { @MainActor in
            try await fixture.exporter.performExport(
                snapshot: snapshot,
                selection: .init(url: fixture.outputURL, format: .standaloneHTML, style: .embedded),
                engine: parser
            )
        }
        await parser.waitForFirstCall()
        let external = Data("new destination fixture".utf8)
        try external.write(to: fixture.outputURL)
        await parser.releaseFirstCall()
        await #expect(throws: ExportError.self) { try await operation.value }
        #expect(try Data(contentsOf: fixture.outputURL) == external)
    }

    @Test func anUnlinkedSourceObjectCannotBeOverwrittenThroughAHardLink() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let source = fixture.directory.appendingPathComponent("source.md")
        let original = Data("# Source fixture".utf8)
        try original.write(to: source)
        let document = try FileDocument(fileURL: source, text: "").load()
        try FileManager.default.linkItem(at: source, to: fixture.outputURL)
        try FileManager.default.removeItem(at: source)
        let snapshot = OrdinaryExportSnapshot(document: document, theme: BundledThemes.light, parseOptions: .default)
        #expect(snapshot.protectedSourceIdentity != nil)
        await #expect(throws: ExportError.self) {
            try await fixture.exporter.performExport(
                snapshot: snapshot,
                selection: .init(url: fixture.outputURL, format: .standaloneHTML, style: .embedded)
            )
        }
        #expect(try Data(contentsOf: fixture.outputURL) == original)
    }

    @Test func snapshotRequestPreservesItsCapturedInputs() {
        let document = FileDocument(
            fileURL: URL(fileURLWithPath: "/tmp/export-snapshot.md"),
            text: "@Note {\nbody\n}\n"
        )
        let snapshot = OrdinaryExportSnapshot(
            document: document,
            theme: BundledThemes.light,
            parseOptions: MarkdownParseOptions(blockDirectives: true)
        )

        let request = snapshot.request(contributions: [])

        #expect(request.text == document.text)
        #expect(request.sourceGeneration == document.mutationGeneration)
        #expect(request.documentURL == document.fileURL)
        #expect(request.resourceAccess === snapshot.resourceAccess)
        #expect(request.resourceAccess != nil)
        #expect(request.theme == BundledThemes.light)
        #expect(request.parseOptions == MarkdownParseOptions(blockDirectives: true))
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ordinary-export-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = OrdinaryExportSettingsStore()
        let settings = AppSettingsModel(store: store)
        let themeController = ThemeController(preferenceStore: OrdinaryExportThemeStore())
        themeController.setAppearance(.light)
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            recoveryBuffer: RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("recovery")),
            themeController: themeController,
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: settings
        )
        let exporter = ExportCoordinator(
            coordinator: coordinator,
            themeController: themeController,
            appSettings: settings
        )
        return Fixture(
            settings: settings,
            themeController: themeController,
            coordinator: coordinator,
            exporter: exporter,
            directory: directory,
            outputURL: directory.appendingPathComponent("result.html")
        )
    }

    private struct Fixture {
        let settings: AppSettingsModel
        let themeController: ThemeController
        let coordinator: WindowCoordinator
        let exporter: ExportCoordinator
        let directory: URL
        let outputURL: URL
    }
}

extension OrdinaryExportSnapshotTests {
    enum LatePublication: Sendable,
        CaseIterable { case controller, activeTab, inactiveTab, stagedController, unlinkedController }

    @Test(arguments: LatePublication.allCases)
    func laterDocumentPublicationPreservesAnUnchangedExportDestination(mode: LatePublication) async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = Data("# Already saved output".utf8)
        try original.write(to: fixture.outputURL)
        let model = fixture.coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: ""))
        let controller = fixture.coordinator.makeWindowController(model: model)
        fixture.coordinator.controllers = [controller]
        defer {
            for item in fixture.coordinator.sessionControllers {
                item.close()
            }
            fixture.coordinator.controllers = []
            fixture.coordinator.commandStdinStages = []
        }
        let parser = GatedExportParseExecutor()
        let snapshot = OrdinaryExportSnapshot(document: FileDocument(text: "# Export source"),
                                              theme: BundledThemes.light, parseOptions: .default)
        let operation = Task { @MainActor in
            try await fixture.exporter.performExport(
                snapshot: snapshot, selection: .init(url: fixture.outputURL, format: .standaloneHTML, style: .embedded),
                engine: parser
            )
        }
        await parser.waitForFirstCall()
        let opened = try FileDocument(fileURL: fixture.outputURL, recoveryBuffer: fixture.coordinator.recoveryBuffer)
            .load()
        switch mode {
        case .controller, .stagedController, .unlinkedController:
            let incoming = fixture.coordinator.makeWindowModel()
            incoming.tabStore.newTab(document: opened)
            let incomingController = fixture.coordinator.makeWindowController(model: incoming)
            if mode != .stagedController {
                fixture.coordinator.controllers.append(incomingController)
            } else {
                fixture.coordinator.commandStdinStages.append(incomingController)
            }
        case .activeTab:
            model.tabStore.newTab(document: opened)
        case .inactiveTab:
            let active = model.tabStore.activeTabID
            model.tabStore.tabs.append(WorkspaceTab(document: opened))
            #expect(model.tabStore.activeTabID == active)
        }
        await parser.releaseFirstCall()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try Data(contentsOf: fixture.outputURL) == original)
    }

    private func laterOpenedDocument(fixture: Fixture, mode: LatePublication) throws -> FileDocument {
        guard mode == .unlinkedController else {
            return try FileDocument(fileURL: fixture.outputURL, recoveryBuffer: fixture.coordinator.recoveryBuffer)
                .load()
        }
        let alias = fixture.directory.appendingPathComponent("vanished-source.md")
        try FileManager.default.linkItem(at: fixture.outputURL, to: alias)
        let loaded = try FileDocument(fileURL: alias, recoveryBuffer: fixture.coordinator.recoveryBuffer).load()
        try FileManager.default.removeItem(at: alias)
        return loaded
    }

    @Test func postFreezeSaveAsUsesTheOriginalSourceAndResourceDirectory() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let oldRoot = fixture.directory.appendingPathComponent("old")
        let newRoot = fixture.directory.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: oldRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newRoot, withIntermediateDirectories: true)
        let sourceURL = oldRoot.appendingPathComponent("source.md")
        let newURL = newRoot.appendingPathComponent("source.md")
        let source = "# Original source\n![image](a.png)\n"
        try Data(source.utf8).write(to: sourceURL)
        try Data([1]).write(to: oldRoot.appendingPathComponent("a.png"))
        try Data([2]).write(to: newRoot.appendingPathComponent("a.png"))
        let loaded = try await FileDocument.create(
            fileURL: sourceURL,
            recoveryBuffer: fixture.coordinator.recoveryBuffer
        ).load()
        let model = fixture.coordinator.makeWindowModel()
        model.tabStore.newTab(document: loaded)
        let controller = fixture.coordinator.makeWindowController(model: model)
        fixture.coordinator.controllers = [controller]
        defer { fixture.coordinator.removeController(controller); controller.close() }
        let tab = model.tabStore.activeTabID
        let origin = try #require(OrdinaryExportOrigin.capture(controller: controller))
        let accepted = try origin.documentAfterPanel()
        let snapshot = OrdinaryExportSnapshot(document: accepted, theme: BundledThemes.light, parseOptions: .default)
        try origin.didFreezeInputs()
        let parser = GatedExportParseExecutor()
        let operation = Task { @MainActor in
            try await fixture.exporter.performExport(
                snapshot: snapshot, selection: .init(url: fixture.outputURL, format: .standaloneHTML, style: .embedded),
                engine: parser, publicationLease: origin.publicationLease
            )
        }
        await parser.waitForFirstCall()
        await model.saveAs(to: newURL, expecting: accepted)
        model.setFolderRoot(newRoot)
        #expect(model.activeDocument?.fileURL == newURL)
        #expect(model.tabStore.activeTabID == tab)
        await parser.releaseFirstCall()
        let result = try await operation.value
        let html = try String(contentsOf: result.primaryFile, encoding: .utf8)
        #expect(html.contains("Original source"))
        let image = try #require(FileManager.default.contentsOfDirectory(
            at: fixture.outputURL.deletingPathExtension().appendingPathExtension("assets"),
            includingPropertiesForKeys: nil
        ).first { $0.pathExtension == "png" })
        #expect(try Data(contentsOf: image) == Data([1]))
        #expect(try Data(contentsOf: sourceURL) == Data(source.utf8))
        #expect(try Data(contentsOf: newRoot.appendingPathComponent("a.png")) == Data([2]))
    }

    @Test func closingTheFrozenOriginWhileParsingStillPreventsPublication() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "# Frozen source"))
        let controller = fixture.coordinator.makeWindowController(model: model)
        fixture.coordinator.controllers = [controller]
        defer { fixture.coordinator.removeController(controller); controller.close() }
        let origin = try #require(OrdinaryExportOrigin.capture(controller: controller))
        let snapshot = try OrdinaryExportSnapshot(document: origin.documentAfterPanel(),
                                                  theme: BundledThemes.light, parseOptions: .default)
        try origin.didFreezeInputs()
        let parser = GatedExportParseExecutor()
        let operation = Task { @MainActor in
            try await fixture.exporter.performExport(
                snapshot: snapshot, selection: .init(url: fixture.outputURL, format: .standaloneHTML, style: .embedded),
                engine: parser, publicationLease: origin.publicationLease
            )
        }
        await parser.waitForFirstCall()
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: controller.window))
        await parser.releaseFirstCall()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(!FileManager.default.fileExists(atPath: fixture.outputURL.path))
    }
}

/// Exports capture themes independently of the owner's saved appearance and theme choices.
private struct OrdinaryExportThemeStore: ThemePreferenceStoring {
    func loadSelection() -> (lightID: String, darkID: String)? {
        (BundledThemes.light.id, BundledThemes.dark.id)
    }

    func saveSelection(lightID _: String, darkID _: String) {}
    func loadAppearanceMode() -> ThemeAppearanceMode? {
        .system
    }

    func saveAppearanceMode(_: ThemeAppearanceMode) {}
}

@MainActor
private final class OrdinaryExportSettingsStore: AppSettingsStoring {
    var general: GeneralSettings = .default
    var editor: EditorSettings = .default
    var markdown: MarkdownSettings = .default
    var previewExport: PreviewExportSettings = .default
    var formats: FormatSettings = .default
}

private actor GatedExportParseExecutor: ParseExecuting {
    struct Call: Sendable {
        let text: String
        let options: MarkdownParseOptions
        let revision: Int
    }

    private(set) var calls: [Call] = []
    private var firstCallGate: CheckedContinuation<Void, Never>?
    private var firstCallWaiters: [CheckedContinuation<Void, Never>] = []

    func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument {
        let isFirstCall = calls.isEmpty
        calls.append(Call(text: text, options: options, revision: revision))
        if isFirstCall {
            let waiters = firstCallWaiters
            firstCallWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                firstCallGate = continuation
            }
        }
        return try await ParseEngine().parse(text, options: options, revision: revision)
    }

    func waitForFirstCall() async {
        guard calls.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            firstCallWaiters.append(continuation)
        }
    }

    func releaseFirstCall() {
        firstCallGate?.resume()
        firstCallGate = nil
    }

    func callsSnapshot() -> [Call] {
        calls
    }
}
