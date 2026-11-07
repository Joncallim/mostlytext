import AppSettings
import Darwin
import EditorCore
import FileCore
import Foundation
@testable import MacDown2
import MarkdownEngine
import Testing
import Workspace

@Suite("AppSettings wiring")
@MainActor
struct AppSettingsWiringTests {
    @Test func currentApplicationDomainFinishesEmptyImportWithoutChangingPreferences() async throws {
        let identity = try #require(Bundle.main.bundleIdentifier)
        try #require(identity == ApplicationStorageLocations.applicationDomain)
        let before = UserDefaults.standard.persistentDomain(forName: identity)
        let store = try UserDefaultsAppSettingsStore(persistentDomainName: identity)
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-current-domain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Foundation can restore the /var alias; the journal deliberately refuses every symlink.
        let physical = try #require(realpath(temporary.path, nil))
        let root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
        free(physical)
        let journal = root.appendingPathComponent("journal", isDirectory: true)
        let startup = LegacyImportStartup(store: store,
                                          makeJournal: { try LegacyEditorMigrationJournal(directoryURL: journal) },
                                          source: { try LegacyPreferenceSnapshot(domain: [:]) },
                                          resolveFont: { _ in nil })
        var readyCount = 0
        startup.didBecomeReady = { readyCount += 1 }
        await startup.begin()
        #expect(startup.phase == .ready)
        #expect(readyCount == 1)
        let after = UserDefaults.standard.persistentDomain(forName: identity)
        #expect(NSDictionary(dictionary: before ?? [:]).isEqual(to: after ?? [:]))
    }

    // MARK: - Markdown

    @Test func markdownParseOptionsReflectsThePreference() {
        let enabled = DocumentEditorSplitView.markdownParseOptions(from: MarkdownSettings(parsesBlockDirectives: true))
        #expect(enabled.blockDirectives)

        let disabled = DocumentEditorSplitView.markdownParseOptions(
            from: MarkdownSettings(parsesBlockDirectives: false)
        )
        #expect(!disabled.blockDirectives)
    }

    @Test func markdownParseOptionsDefaultsToOnWhenSettingsUnavailable() {
        #expect(!DocumentEditorSplitView.markdownParseOptions(from: nil).blockDirectives)
    }

    // MARK: - Editor assists

    @Test func assistConfigurationReflectsEveryFieldForMarkdown() {
        let settings = EditorSettings(
            indentationWidth: 2,
            assistsEnabled: false,
            continuesMarkdownPrefixes: false,
            completesMatchingCharacters: false,
            convertsTabsToSpaces: false,
            smartHome: false,
            autoIncrementOrderedLists: false
        )
        let config = DocumentEditorSplitView.assistConfiguration(from: settings, isMarkdown: true)
        #expect(!config.isEnabled)
        #expect(!config.continuesMarkdownPrefixes)
        #expect(!config.completesMatchingCharacters)
        #expect(!config.completesMarkdownDelimiters)
        #expect(!config.convertsTabsToSpaces)
        #expect(!config.smartHome)
        #expect(!config.autoIncrementOrderedLists)
        #expect(config.indentationWidth == 2)
    }

    /// EPIC-22 §6.11, Slice 4a: for a non-Markdown format, the Markdown-only
    /// fields are forced off regardless of the user's own setting, while the
    /// general mechanics still respect it.
    @Test func assistConfigurationForcesMarkdownOnlyFieldsOffForOtherFormats() {
        let settings = EditorSettings(
            indentationWidth: 2,
            assistsEnabled: true,
            continuesMarkdownPrefixes: true,
            completesMatchingCharacters: true,
            convertsTabsToSpaces: true,
            smartHome: true,
            autoIncrementOrderedLists: true
        )
        let config = DocumentEditorSplitView.assistConfiguration(from: settings, isMarkdown: false)
        #expect(config.isEnabled)
        #expect(!config.continuesMarkdownPrefixes)
        #expect(config.completesMatchingCharacters)
        #expect(!config.completesMarkdownDelimiters)
        #expect(config.convertsTabsToSpaces)
        #expect(config.smartHome)
        #expect(!config.autoIncrementOrderedLists)
    }

    @Test func assistConfigurationFallsBackToMarkdownDefaultWhenSettingsUnavailable() {
        #expect(DocumentEditorSplitView.assistConfiguration(from: nil, isMarkdown: true) == .markdownDefault)
    }

    @Test func assistConfigurationFallsBackToGeneralWhenSettingsUnavailableForOtherFormats() {
        #expect(DocumentEditorSplitView.assistConfiguration(from: nil, isMarkdown: false) == .general)
    }

    // MARK: - Preview layout

    @Test func defaultPreviewLayoutMapsEachPreference() {
        #expect(
            DocumentEditorSplitView.defaultPreviewLayout(
                from: PreviewExportSettings(defaultPreviewLayout: .editorOnly)
            ) == .editorOnly
        )
        #expect(
            DocumentEditorSplitView.defaultPreviewLayout(
                from: PreviewExportSettings(defaultPreviewLayout: .split)
            ) == .defaultMode
        )
        #expect(
            DocumentEditorSplitView.defaultPreviewLayout(
                from: PreviewExportSettings(defaultPreviewLayout: .previewOnly)
            ) == .previewOnly
        )
    }

    @Test func defaultPreviewLayoutFallsBackToDefaultModeWhenSettingsUnavailable() {
        #expect(DocumentEditorSplitView.defaultPreviewLayout(from: nil) == .defaultMode)
    }

    // MARK: - Export defaults

    @Test func exportFormatOptionMapsEachPreference() {
        #expect(ExportCoordinator.exportFormatOption(from: .standaloneHTML) == .standaloneHTML)
        #expect(ExportCoordinator.exportFormatOption(from: .selfContainedHTML) == .selfContainedHTML)
        #expect(ExportCoordinator.exportFormatOption(from: .pdf) == .pdf)
    }

    @Test func exportStyleEmbeddingMapsEachPreference() {
        #expect(ExportCoordinator.exportStyleEmbedding(from: .embedded) == .embedded)
        #expect(ExportCoordinator.exportStyleEmbedding(from: .linked) == .linked)
    }

    // MARK: - Format encoding

    @Test func defaultEncodingMapsUTF16ToTheLittleEndianBOMForm() {
        let resolved = WindowCoordinator.defaultEncoding(from: FormatSettings(defaultEncodingForNewDocuments: "utf-16"))
        #expect(resolved == FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian))
    }

    @Test func defaultEncodingMapsUTF8ToTheDocumentedDefault() {
        let resolved = WindowCoordinator.defaultEncoding(from: FormatSettings(defaultEncodingForNewDocuments: "utf-8"))
        #expect(resolved == .utf8Default)
    }

    @Test func defaultEncodingFallsBackToUTF8ForAnUnrecognisedValue() {
        let resolved = WindowCoordinator.defaultEncoding(
            from: FormatSettings(defaultEncodingForNewDocuments: "shift-jis")
        )
        #expect(resolved == .utf8Default)
    }
}
