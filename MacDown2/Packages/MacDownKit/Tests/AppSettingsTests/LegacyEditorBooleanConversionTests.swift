@testable import AppSettings
import Foundation
import Testing

@Suite("Legacy editor Boolean conversion")
struct LegacyEditorBooleanConversionTests {
    @Test func preservesBothExplicitBooleanValuesAndLeavesOtherKeysUnmapped() throws {
        let snapshot = try LegacyPreferenceSnapshot(domain: [
            "editorAutoIncrementNumberedLists": false,
            "editorConvertTabs": true,
            "editorSmartHome": false,
            "editorInsertPrefixInBlock": true,
            "editorBaseFontInfo": ["name": "Menlo"],
        ])
        let conversion = LegacyEditorBooleanConversion(snapshot: snapshot)

        #expect(conversion.proposedValues == [
            .autoIncrementOrderedLists: false,
            .convertsTabsToSpaces: true,
            .smartHome: false,
        ])
        #expect(conversion.invalidSourceKeys.isEmpty)
        #expect(snapshot.values["editorInsertPrefixInBlock"] == .boolean(true))
        #expect(snapshot.values["editorBaseFontInfo"] != nil)
    }

    @Test func absentKeysDoNotInventAnExplicitLegacyPreference() throws {
        let snapshot = try LegacyPreferenceSnapshot(domain: ["unrelated": "value"])
        let conversion = LegacyEditorBooleanConversion(snapshot: snapshot)
        #expect(conversion.proposedValues.isEmpty)
        #expect(conversion.invalidSourceKeys.isEmpty)
    }

    @Test func numericAndStringLookalikesCannotBecomeBooleanSettings() throws {
        let snapshot = try LegacyPreferenceSnapshot(domain: [
            "editorAutoIncrementNumberedLists": 0,
            "editorConvertTabs": "true",
            "editorSmartHome": Data([0]),
        ])
        let conversion = LegacyEditorBooleanConversion(snapshot: snapshot)
        #expect(conversion.proposedValues.isEmpty)
        #expect(conversion.invalidSourceKeys == [
            "editorAutoIncrementNumberedLists",
            "editorConvertTabs",
            "editorSmartHome",
        ])
    }
}
