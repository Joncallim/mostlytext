@testable import AppSettings
import Foundation
import Testing

/// #53 SETTINGS-COMPAT: old readable values remain compatible, while unreadable primary values
/// remain in place across ordinary writes. The first backup is retained for compatibility;
/// migration/conversion and explicit recovery acceptance remain separate work.
@MainActor
struct SettingsCompatibilityTests {
    private static let editorKey = "appSettings.editor"

    private func isolated(_ body: (UserDefaults, UserDefaultsAppSettingsStore) throws -> Void) rethrows {
        let suite = UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("no suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, UserDefaultsAppSettingsStore(defaults: defaults))
    }

    private func editorJSON(
        statusBar: String? = nil,
        fontSize: String = "15",
        fontExtra: String? = nil,
        width: String = "2",
        extra: String = "",
        omit: String? = nil
    ) -> Data {
        var fields = [
            "\"font\":{\"familyName\":\"Menlo\",\"size\":\(fontSize)\(fontExtra.map { ",\($0)" } ?? "")}",
            "\"wrapsLines\":false",
            "\"showsInvisibles\":true",
            "\"indentationWidth\":\(width)",
            "\"assistsEnabled\":false",
            "\"continuesMarkdownPrefixes\":false",
            "\"completesMatchingCharacters\":false",
            "\"convertsTabsToSpaces\":false",
            "\"smartHome\":false",
            "\"autoIncrementOrderedLists\":false",
        ]
        if let statusBar {
            fields.append("\"showsStatusBar\":\(statusBar)")
        }
        if !extra.isEmpty {
            fields.append(extra)
        }
        if let omit {
            fields.removeAll { $0.hasPrefix("\"\(omit)\"") }
        }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    @Test func aPreE22BlobKeepsEveryUserValueAndDefaultsOnlyTheMissingField() {
        isolated { defaults, store in
            defaults.set(editorJSON(), forKey: Self.editorKey)

            let editor = store.editor

            #expect(editor.font == FontDescriptor(familyName: "Menlo", size: 15))
            #expect(editor.indentationWidth == 2)
            #expect(!editor.assistsEnabled && !editor.wrapsLines && !editor.smartHome)
            #expect(editor.showsInvisibles)
            #expect(editor.showsStatusBar, "the one missing additive field takes its documented default")
            #expect(store.unreadableDomains.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func aPresentBooleanStatusBarKeepsItsValue(value: Bool) {
        isolated { defaults, store in
            let original = editorJSON(statusBar: String(value))
            defaults.set(original, forKey: Self.editorKey)
            #expect(store.editor.showsStatusBar == value)
            #expect(store.unreadableDomains.isEmpty)
            #expect(defaults.data(forKey: Self.editorKey) == original)
        }
    }

    @Test(arguments: ["null", "0", "\"false\"", "[]", "{}"])
    func aPresentMalformedStatusBarIsUnreadableNotAMissingField(value: String) {
        isolated { defaults, store in
            let invalid = editorJSON(statusBar: value)
            defaults.set(invalid, forKey: Self.editorKey)

            #expect(store.editor == .default, "malformed input uses only the session fallback")
            #expect(store.unreadableDomains == [Self.editorKey])
            #expect(defaults.data(forKey: Self.editorKey) == invalid, "loading cannot rewrite malformed data")
        }
    }

    @Test func aMissingOldMandatoryFieldIsUnreadableAndTheRawBytesSurviveASave() {
        isolated { defaults, store in
            var store = store
            let original = editorJSON(omit: "font")
            defaults.set(original, forKey: Self.editorKey)

            #expect(store.editor == .default, "session fallback only")
            #expect(store.unreadableDomains == [Self.editorKey])
            #expect(defaults.data(forKey: Self.editorKey) == original, "loading never rewrites the blob")

            store.editor = EditorSettings(indentationWidth: 3)

            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == original)
            #expect(defaults.data(forKey: Self.editorKey) == original)
            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])
        }
    }

    @Test(arguments: ["0", "9", "-1", "\"wide\"", "2.5"])
    func anInvalidOrOutOfRangeIndentationIsUnreadableNotSilentlyClamped(width: String) {
        isolated { defaults, store in
            defaults.set(editorJSON(width: width), forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])
        }
    }

    @Test(arguments: ["0", "-1"])
    func anInvalidPersistedFontSizeIsUnreadableAndPreserved(size: String) {
        isolated { defaults, store in
            var store = store
            let invalid = editorJSON(fontSize: size)
            defaults.set(invalid, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])
            #expect(defaults.data(forKey: Self.editorKey) == invalid, "loading never rewrites the invalid blob")

            store.editor = EditorSettings(indentationWidth: 5)
            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == invalid)
        }
    }

    @Test func aLargeButSupportedPersistedFontSizeIsKept() {
        isolated { defaults, store in
            defaults.set(editorJSON(fontSize: "1000"), forKey: Self.editorKey)

            #expect(store.editor.font.size == 1000)
            #expect(store.unreadableDomains.isEmpty)
        }
    }

    /// Review of the combined tree: a persisted size of 1e100 was accepted and then trapped the Settings pane's
    /// `Int(size)` label. Sizes beyond the supported bound are unreadable and preserved, never applied.
    @Test(arguments: ["1000.5", "1e100", "1.7976931348623157e308"])
    func aPersistedFontSizeBeyondTheSupportedBoundIsUnreadableAndPreserved(size: String) {
        isolated { defaults, store in
            let invalid = editorJSON(fontSize: size)
            defaults.set(invalid, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])
            #expect(defaults.data(forKey: Self.editorKey) == invalid, "loading never rewrites the invalid blob")
        }
    }

    @Test func aCurrentOrAbsentSchemaVersionIsReadable() {
        isolated { defaults, store in
            defaults.set(editorJSON(extra: "\"schemaVersion\":1"), forKey: Self.editorKey)
            #expect(store.editor.indentationWidth == 2)
            #expect(store.unreadableDomains.isEmpty)

            defaults.removeObject(forKey: Self.editorKey)
            defaults.set(editorJSON(), forKey: Self.editorKey)
            #expect(store.editor.indentationWidth == 2)
            #expect(store.unreadableDomains.isEmpty)
        }
    }

    /// A schema-less historical blob cannot distinguish an additive field from
    /// a value written by a newer schema-less build. Reject the whole blob so
    /// an ordinary edit cannot silently discard that unknown field (#53).
    @Test func aSchemaLessUnknownFieldIsProtectedFromAnOrdinaryEditorSave() {
        isolated { defaults, store in
            var store = store
            let original = editorJSON(extra: "\"unknownFutureField\":\"retain me\"")
            defaults.set(original, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])

            store.editor = EditorSettings(indentationWidth: 3)

            #expect(defaults.data(forKey: Self.editorKey) == original)
            let reopened = UserDefaultsAppSettingsStore(defaults: defaults)
            #expect(reopened.editor == .default)
            #expect(reopened.unreadableDomains == [Self.editorKey])
        }
    }

    @Test(arguments: ["Inf", "-Inf", "NaN"])
    func nonFiniteFontSizesAreRejectedByTheDecodingBoundary(value: String) {
        let data = Data("{\"familyName\":\"Menlo\",\"size\":\"\(value)\"}".utf8)
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Inf", negativeInfinity: "-Inf", nan: "NaN"
        )

        #expect(throws: DecodingError.self) {
            try decoder.decode(FontDescriptor.self, from: data)
        }
    }

    @Test(arguments: [
        "0", "-1", "true", "false", "\"1\"", "1.5", "9223372036854775808", "-9223372036854775809",
        "1e100", "-1e100", "1e400", "-1e400",
    ])
    func anInvalidDeclaredSchemaVersionIsUnreadableAndPreserved(version: String) {
        isolated { defaults, store in
            var store = store
            let invalid = editorJSON(extra: "\"schemaVersion\":\(version)")
            defaults.set(invalid, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])
            #expect(defaults.data(forKey: Self.editorKey) == invalid, "loading never rewrites the invalid blob")

            store.editor = EditorSettings(indentationWidth: 5)
            #expect(defaults.data(forKey: Self.editorKey) == invalid)
            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])
            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == invalid)
        }
    }

    @Test func anUnparseableFutureSchemaPayloadIsUnreadableAndPreserved() {
        isolated { defaults, store in
            var store = store
            let invalid = editorJSON(extra: "\"schemaVersion\":2,\"futureOnlyField\":1e400")
            defaults.set(invalid, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])
            #expect(defaults.data(forKey: Self.editorKey) == invalid, "loading never rewrites the invalid blob")

            store.editor = EditorSettings(indentationWidth: 5)
            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == invalid)
        }
    }

    @Test func corruptBytesAreRetainedAndReported() {
        isolated { defaults, store in
            var store = store
            let corrupt = Data([0x7B, 0xFF, 0x00, 0x22])
            defaults.set(corrupt, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])

            store.editor = .default
            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == corrupt)
        }
    }

    @Test func theFirstUnreadableBlobIsKeptAndRepeatedReadsDoNotWrite() {
        isolated { defaults, store in
            var store = store
            let first = Data("not json".utf8)
            defaults.set(first, forKey: Self.editorKey)
            store.editor = EditorSettings(indentationWidth: 2) // preserves `first` without replacing the primary
            let second = Data("also not json".utf8)
            defaults.set(second, forKey: Self.editorKey) // a second unreadable generation
            store.editor = EditorSettings(indentationWidth: 3)

            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == first, "never overwritten once kept")
            #expect(defaults.data(forKey: Self.editorKey) == second, "the second generation remains at the primary")

            // Repeated reads are stable and never write.
            let written = defaults.data(forKey: Self.editorKey)
            _ = store.editor
            _ = store.editor
            #expect(defaults.data(forKey: Self.editorKey) == written)
        }
    }

    @Test func validCurrentDataRoundTripsWithoutPreservingAnything() {
        isolated { defaults, store in
            var store = store
            store.editor = EditorSettings(showsStatusBar: false, indentationWidth: 6)
            store.editor = EditorSettings(showsStatusBar: false, indentationWidth: 7)

            #expect(store.editor.indentationWidth == 7 && !store.editor.showsStatusBar)
            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == nil)
            #expect(defaults.data(forKey: Self.editorKey + ".preservedUnreadable") == nil)
        }
    }
}

extension SettingsCompatibilityTests {
    @Test(arguments: ["1.0000000000000001", "0.99999999999999999"])
    func fractionalSchemaVersionIsPreservedBeforeFoundationCanRoundIt(version: String) {
        isolated { defaults, store in
            var store = store
            let raw = editorJSON(extra: "\"schemaVersion\":\(version)")
            defaults.set(raw, forKey: Self.editorKey)

            // The raw parser can now distinguish these fractions from 1.
            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])
            store.editor = EditorSettings(indentationWidth: 5)
            #expect(defaults.data(forKey: Self.editorKey) == raw)
        }
    }

    @Test func aNewerSchemaVersionStaysAtItsPrimaryKeyAfterAnOrdinarySave() {
        isolated { defaults, store in
            var store = store
            let future = editorJSON(extra: "\"schemaVersion\":2,\"futureOnlyField\":\"keep me\"")
            defaults.set(future, forKey: Self.editorKey)

            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.editorKey])

            store.editor = EditorSettings(indentationWidth: 5)
            #expect(store.preservedUnreadableData(forDomain: Self.editorKey) == future)
            #expect(defaults.data(forKey: Self.editorKey) == future)
        }
    }
}
