@testable import EditorCore
import Foundation
import Testing

@Suite("Snippet library, catalog and store (EPIC-22 Slice 9e)")
struct SnippetLibraryTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("snippets-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    @Test func aMissingFileLoadsAsMissing() {
        #expect(SnippetStore(fileURL: tempFile()).load() == .missing)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = SnippetStore(fileURL: tempFile())
        let snippet = Snippet(id: "u1", name: "Todo", body: "TODO: $0", scopes: ["markdown"])
        let library = SnippetLibrary(snippets: [snippet])
        try store.save(library)
        #expect(store.load() == .loaded(library))
    }

    @Test func aMalformedElementIsSkippedWithoutLosingTheOthers() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"version":1,"snippets":[
          {"id":"a","name":"Good","body":"x"},
          {"id":"b","name":"No body"},
          {"id":"","name":"Empty id","body":"y"},
          {"id":"c","name":"  ","body":"blank name"},
          {"id":"d","name":"Scoped","body":"z","scopes":["json"]}
        ]}
        """
        try Data(json.utf8).write(to: url)
        guard case let .loaded(library) = SnippetStore(fileURL: url).load() else {
            Issue.record("expected a loaded library")
            return
        }
        #expect(library.snippets.map(\.id) == ["a", "d"])
        #expect(library.skippedCount == 3)
        #expect(library.snippets.first?.scopes.isEmpty == true)
    }

    @Test func garbageIsUnreadableAndIsNeverOverwrittenByALoadOrCreateIfMissing() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = SnippetStore(fileURL: url)
        #expect(store.load() == .unreadable)
        #expect(store.createIfMissing())
        #expect(try Data(contentsOf: url) == Data("not json".utf8))
    }

    @Test func aNewerVersionIsReportedNotDowngraded() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":99,"snippets":[]}"#.utf8).write(to: url)
        #expect(SnippetStore(fileURL: url).load() == .unsupportedVersion(99))
        #expect(SnippetStore(fileURL: url).load().snippets.isEmpty)
    }

    @Test func createIfMissingWritesAnEmptyLibraryOnce() {
        let store = SnippetStore(fileURL: tempFile())
        #expect(store.createIfMissing())
        #expect(store.load() == .loaded(SnippetLibrary()))
    }

    @Test func createIfMissingNeverReplacesAFileThatAppearedFirst() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":1,"snippets":[{"id":"k","name":"Keep","body":"k"}]}"#.utf8).write(to: url)
        #expect(SnippetStore(fileURL: url).createIfMissing())
        let kept = SnippetStore(fileURL: url).load().snippets.map(\.id)
        #expect(kept == ["k"])
    }

    @Test func catalogScopesByFormatAndSortsByName() {
        let user = [
            Snippet(id: "u1", name: "Zeta", body: "z"),
            Snippet(id: "u2", name: "Only JSON", body: "j", scopes: ["json"]),
        ]
        let markdown = SnippetCatalog.snippets(user: user, formatID: "markdown")
        #expect(markdown.contains { $0.id == "u1" })
        #expect(!markdown.contains { $0.id == "u2" })
        #expect(markdown.map(\.name) == markdown.map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending })

        let json = SnippetCatalog.snippets(user: user, formatID: "json")
        #expect(json.map(\.id).contains("u2"))
        #expect(!json.contains { $0.id.hasPrefix("builtin.markdown") })
    }

    @Test func aUserSnippetWithABuiltInIdReplacesIt() {
        let override = Snippet(id: "builtin.markdown.link", name: "My own link", body: "<$0>", scopes: ["markdown"])
        let result = SnippetCatalog.snippets(user: [override], formatID: "markdown")
        #expect(result.filter { $0.id == "builtin.markdown.link" }.map(\.body) == ["<$0>"])
        #expect(result.filter { $0.id == "builtin.markdown.link" }.map(\.name) == ["My own link"])
    }

    @Test func filterMatchesNamesCaseAndDiacriticInsensitively() {
        let all = [Snippet(id: "1", name: "Café Menu", body: ""), Snippet(id: "2", name: "Table", body: "")]
        #expect(SnippetCatalog.filter(all, query: "cafe").map(\.id) == ["1"])
        #expect(SnippetCatalog.filter(all, query: "  ").count == 2)
        #expect(SnippetCatalog.filter(all, query: "zzz").isEmpty)
    }

    @Test func everyBuiltInIsUsableAndHasAUniqueId() {
        let ids = BuiltInSnippets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        // swiftformat rewrites `allSatisfy { $0.isUsable }` to a key path, which #expect cannot infer as non-throwing.
        #expect(BuiltInSnippets.all.filter { !$0.isUsable }.isEmpty)
    }

    @Test func builtInDisplayNamesResolveFromTheirBundleWithoutChangingSnippetIdentity() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippet-localization-\(UUID().uuidString).bundle", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        let resources = bundleURL.appendingPathComponent("Contents/Resources/fr.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: String] = [
            "CFBundleIdentifier": "app.mostlytext.snippet-localization-test.\(UUID().uuidString)",
            "CFBundleDevelopmentRegion": "fr",
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        let translations = [
            ("Fenced Code Block", "FR_CODE_SENTINEL"),
            ("Link", "FR_LINK_SENTINEL"),
            ("Link from Clipboard", "FR_CLIPBOARD_SENTINEL"),
            ("Image", "FR_IMAGE_SENTINEL"),
            ("Table", "FR_TABLE_SENTINEL"),
            ("Task", "FR_TASK_SENTINEL"),
        ]
        let strings = translations.map { "\"\($0.0)\" = \"\($0.1)\";" }.joined(separator: "\n")
        try strings.write(
            to: resources.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )
        let fixture = try #require(Bundle(url: bundleURL))

        let originals = BuiltInSnippets.all
        let localized = BuiltInSnippets.all(in: fixture)
        #expect(localized.map(\.name) == translations.map(\.1))
        #expect(localized.map(\.id) == originals.map(\.id))
        #expect(localized.map(\.body) == originals.map(\.body))
        #expect(localized.map(\.scopes) == originals.map(\.scopes))

        let override = Snippet(id: "builtin.markdown.link", name: "My own link", body: "<$0>", scopes: ["markdown"])
        let merged = SnippetCatalog.snippets(user: [override], formatID: "markdown", builtIn: localized)
        #expect(merged.first { $0.id == override.id }?.name == "My own link")
        #expect(SnippetCatalog.filter(merged, query: "FR_CODE_SENTINEL").map(\.id) == ["builtin.markdown.codeBlock"])
    }
}
