import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// EPIC-22 §6.18, Slice 9e — picker model logic and the coordinator-level
/// insert path (origin targeting, clipboard, one undo step).
@MainActor
@Suite("SnippetPicker")
struct SnippetPickerTests {
    private static let snippets = [
        Snippet(id: "a", name: "Alpha Block", body: "A"),
        Snippet(id: "b", name: "Beta Link", body: "B"),
        Snippet(id: "c", name: "Gamma Block", body: "C"),
    ]

    @Test func emptyQueryShowsEverything() {
        let model = SnippetPickerModel(snippets: Self.snippets)
        #expect(model.results.map(\.id) == ["a", "b", "c"])
        #expect(model.selectedSnippet?.id == "a")
    }

    @Test func queryFiltersAndResetsSelection() {
        let model = SnippetPickerModel(snippets: Self.snippets)
        model.moveSelection(by: 2)
        model.query = "block"
        #expect(model.results.map(\.id) == ["a", "c"])
        #expect(model.selectedIndex == 0)
    }

    @Test func selectionWrapsBothWays() {
        let model = SnippetPickerModel(snippets: Self.snippets)
        model.moveSelection(by: -1)
        #expect(model.selectedSnippet?.id == "c")
        model.moveSelection(by: 1)
        #expect(model.selectedSnippet?.id == "a")
    }

    @Test func noMatchLeavesNothingSelectedAndMovementIsANoOp() {
        let model = SnippetPickerModel(snippets: Self.snippets)
        model.query = "zzz"
        model.moveSelection(by: 1)
        #expect(model.results.isEmpty)
        #expect(model.selectedSnippet == nil)
    }

    private struct Fixture {
        let coordinator: WindowCoordinator
        let controller: WindowController
        let system: EditorTextSystem
    }

    private func makeFixture(text: String) throws -> Fixture {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: text))
        let tabID = try #require(model.tabStore.activeTab).id
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        system.setAwaitingEditorView(false) // these tests drive the system without an EditorView
        return Fixture(coordinator: coordinator, controller: controller, system: system)
    }

    @Test func insertExpandsAtTheOriginEditorAndUndoesInOneStep() throws {
        let fixture = try makeFixture(text: "x")
        let (coordinator, controller, system) = (fixture.coordinator, fixture.controller, fixture.system)
        system.textView.setSelectedRange(NSRange(location: 1, length: 0))
        let snippet = Snippet(id: "t", name: "T", body: "[$0]")

        #expect(coordinator.insertSnippet(snippet, into: controller))
        #expect(system.textView.string == "x[]")
        #expect(system.textView.selectedRange() == NSRange(location: 2, length: 0))
        system.textView.undoManager?.undo()
        #expect(system.textView.string == "x")
    }

    @Test func userSnippetsMergeWithBuiltInsAndScopeToTheFormat() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnippetStore(fileURL: directory.appendingPathComponent("snippets.json"))
        try store.save(SnippetLibrary(snippets: [
            Snippet(id: "u1", name: "Only JSON", body: "{}", scopes: ["json"]),
        ]))
        let coordinator = try makeFixture(text: "").coordinator

        let markdown = coordinator.availableSnippets(formatID: "markdown", store: store)
        let json = coordinator.availableSnippets(formatID: "json", store: store)

        #expect(markdown.contains { $0.id == "builtin.markdown.table" || $0.id.hasPrefix("builtin.markdown") })
        #expect(!markdown.contains { $0.id == "u1" })
        #expect(json.map(\.id) == ["u1"])
    }

    @Test func unreadableSnippetFileOffersOnlyBuiltInsAndIsNotRewritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("snippets.json")
        try Data("not json".utf8).write(to: url)
        let coordinator = try makeFixture(text: "").coordinator

        let offered = coordinator.availableSnippets(formatID: "markdown", store: SnippetStore(fileURL: url))

        #expect(!offered.isEmpty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "not json")
    }

    @Test func insertIsRefusedWhenTheActiveTabChangedSinceThePickerOpened() throws {
        let fixture = try makeFixture(text: "x")
        let openedFor = try #require(fixture.controller.model.tabStore.activeTab).id
        fixture.controller.model.tabStore.newTab(document: FileDocument(text: "other"))

        let inserted = fixture.coordinator.insertSnippet(
            Snippet(id: "t", name: "T", body: "!"),
            into: fixture.controller,
            expectingTab: openedFor
        )

        #expect(!inserted)
        #expect(fixture.system.textView.string == "x")
    }

    @Test func multiCaretInsertIsOneUndoStep() throws {
        let fixture = try makeFixture(text: "a\nb")
        fixture.system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)],
            primaryIndex: 0
        )

        #expect(fixture.coordinator.insertSnippet(Snippet(id: "t", name: "T", body: "<$0>"), into: fixture.controller))
        #expect(fixture.system.textView.string == "a<>\nb<>")
        fixture.system.textView.undoManager?.undo()
        #expect(fixture.system.textView.string == "a\nb")
    }

    @Test func noticeExplainsAnUnusableOrPartiallyUsableSnippetFile() {
        #expect(WindowCoordinator.snippetNotice(for: .missing) == nil)
        #expect(WindowCoordinator.snippetNotice(for: .loaded(SnippetLibrary())) == nil)
        #expect(WindowCoordinator.snippetNotice(for: .unreadable) != nil)
        #expect(WindowCoordinator.snippetNotice(for: .unsupportedVersion(9)) != nil)
    }

    @Test func snippetFileNoticesFollowTheSelectedPanelLocale() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippet-notice-locales-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        for (language, prefix) in [("en", "EN"), ("fr", "FR")] {
            let directory = root.appendingPathComponent("Contents/Resources/\(language).lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let values = """
            "snippets.json could not be read; showing built-in snippets only." = "\(prefix)_UNREADABLE";
            "snippets.json is from a newer version; showing built-in snippets only." = "\(prefix)_NEWER";
            "%lld entries in snippets.json were skipped." = "\(prefix)_%lld_SKIPPED";
            """
            try values.write(to: directory.appendingPathComponent("Localizable.strings"),
                             atomically: true, encoding: .utf8)
        }
        let bundle = try #require(Bundle(url: root))
        let partial = try JSONDecoder().decode(SnippetLibrary.self, from: Data("""
        {"version":1,"snippets":[{"id":"bad"}]}
        """.utf8))
        #expect(partial.skippedCount == 1)
        for (language, prefix) in [("en", "EN"), ("fr", "FR")] {
            let locale = Locale(identifier: language)
            #expect(WindowCoordinator.snippetNotice(for: .unreadable, locale: locale, bundle: bundle)
                == "\(prefix)_UNREADABLE")
            #expect(WindowCoordinator.snippetNotice(for: .unsupportedVersion(9), locale: locale, bundle: bundle)
                == "\(prefix)_NEWER")
            #expect(WindowCoordinator.snippetNotice(for: .loaded(partial), locale: locale, bundle: bundle)
                == "\(prefix)_1_SKIPPED")
        }
    }
}
