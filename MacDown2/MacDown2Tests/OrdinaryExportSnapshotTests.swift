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
import Workspace

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
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.text == source })
        #expect(calls.allSatisfy { $0.options == .default })
        #expect(calls.allSatisfy { $0.revision == Int(document.mutationGeneration) })
        #expect(html.contains(ExportThemeStylesheet.variables(for: BundledThemes.light)))
        #expect(!html.contains(ExportThemeStylesheet.variables(for: BundledThemes.dark)))
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
            exporter: exporter,
            directory: directory,
            outputURL: directory.appendingPathComponent("result.html")
        )
    }

    private struct Fixture {
        let settings: AppSettingsModel
        let themeController: ThemeController
        let exporter: ExportCoordinator
        let directory: URL
        let outputURL: URL
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
