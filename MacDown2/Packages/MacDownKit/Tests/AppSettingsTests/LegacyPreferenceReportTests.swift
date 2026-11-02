import AppSettings
import Foundation
import Testing

@Suite("Complete legacy preference report")
struct LegacyPreferenceReportTests {
    private func report(_ values: [String: Any]) throws -> [String: LegacyPreferenceReport.Disposition] {
        let snapshot = try LegacyPreferenceSnapshot(domain: values)
        return Dictionary(uniqueKeysWithValues: LegacyPreferenceReport(snapshot: snapshot).entries.map {
            ($0.key, $0.disposition)
        })
    }

    @Test func everyDeclaredKeyHasADataOnlyDisposition() throws {
        var values: [String: Any] = [:]
        for definition in LegacyPreferenceCatalog.definitions {
            switch definition.valueKind {
            case .boolean: values[definition.key] = true
            case .string: values[definition.key] = "Example"
            case .number, .enumeration: values[definition.key] = 2
            case .font: values[definition.key] = ["name": "Menlo-Regular", "size": 14]
            case .opaque: values[definition.key] = Data([0, 1])
            }
        }
        let result = try report(values)
        #expect(LegacyPreferenceCatalog.definitions.count == 58)
        #expect(result.count == 58)
        #expect(result.values.allSatisfy { $0 != .unknown && $0 != .invalid })
        #expect(result["editorShowWordCount"] == .unsupported)
        #expect(result["editorInsertPrefixInBlock"] == .unsupported)
        #expect(result["editorCompleteMatchingCharacters"] == .unsupported)
        #expect(result["htmlDefaultDirectoryUrl"] == .unsupported)
    }

    @Test(arguments: [true, false])
    func directBooleansPreserveTheExplicitValue(value: Bool) throws {
        let result = try report([
            "editorSmartHome": value, "editorAutoIncrementNumberedLists": value,
            "editorConvertTabs": value,
        ])
        #expect(result["editorSmartHome"] == .editorBoolean(.smartHome, value))
        #expect(result["editorAutoIncrementNumberedLists"] == .editorBoolean(.autoIncrementOrderedLists, value))
        #expect(result["editorConvertTabs"] == .editorBoolean(.convertsTabsToSpaces, value))
    }

    @Test(arguments: ["extensionTables", "extensionFencedCode", "extensionStrikethough", "htmlTaskList"])
    func unconditionalGrammarNeverCreatesAToggle(key: String) throws {
        #expect(try report([key: true])[key] == .unconditionalCapability)
        #expect(try report([key: false])[key] == .unsupported)
        #expect(try report([key: 1])[key] == .invalid)
    }

    @Test func noCaseSuffixOrCorrectedSpellingAliases() throws {
        let result = try report([
            "editor.smartHome": true, "EditorSmartHome": true,
            "extensionStrikethrough": true, "supressesUntitledDocumentOnLaunch": true,
        ])
        #expect(result["editor.smartHome"] == .unknown)
        #expect(result["EditorSmartHome"] == .unknown)
        #expect(result["extensionStrikethrough"] == .unknown)
        #expect(result["supressesUntitledDocumentOnLaunch"] == .unsupported)
    }

    @Test func enumAndBooleanLookalikesAreRejected() throws {
        let result = try report([
            "editorSmartHome": "false", "htmlHardWrap": 1,
            "editorWordCountType": true, "htmlCodeBlockAccessory": 0.5,
            "editorUnorderedListMarkerType": 3, "editorHorizontalInset": "15",
        ])
        #expect(result.values.allSatisfy { $0 == .invalid })
    }

    @Test func ipcCalculatedAndUnknownDataCannotBecomeAnImport() throws {
        let result = try report([
            "filesToOpen": ["/private/owner-secret"],
            "pipedContentFileToOpen": "/private/owner-secret",
            "editorBaseFont": Data([255]), "SUFeedURL": "https://example.invalid",
            "htmlDefaultDirectoryUrl": Data([255]),
        ])
        #expect(result["filesToOpen"] == .ignoredTransient)
        #expect(result["pipedContentFileToOpen"] == .ignoredTransient)
        #expect(result["editorBaseFont"] == .calculatedValue)
        #expect(result["SUFeedURL"] == .unknown)
        #expect(result["htmlDefaultDirectoryUrl"] == .unsupported)
    }

    @Test func fontRequestRequiresExactInstalledResolutionInsteadOfAFamilyGuess() throws {
        let result = try report(["editorBaseFontInfo": ["name": "Missing-Oblique", "size": 14]])
        guard case let .requiresExactInstalledFont(request) = result["editorBaseFontInfo"] else {
            Issue.record("Expected an unresolved font request")
            return
        }
        #expect(request.postScriptName == "Missing-Oblique")
        #expect(request.size == 14)
    }

    @Test func malformedFontObjectsStayInvalid() throws {
        let objects: [[String: Any]] = [
            ["name": "Menlo-Regular"], ["name": "Menlo-Regular", "size": true],
            ["name": "Menlo-Regular", "size": 0], ["name": "Menlo-Regular", "size": 1001],
            ["name": "Menlo-Regular", "size": 14, "script": "ignored()"],
            ["name": "Bad\0Name", "size": 14],
        ]
        for object in objects {
            #expect(try report(["editorBaseFontInfo": object])["editorBaseFontInfo"] == .invalid)
        }
    }

    @Test func reportIsStableAndDoesNotInventAbsentSourceValues() throws {
        let first = try LegacyPreferenceSnapshot(domain: ["editorSmartHome": false, "unknown": "value"])
        let reordered = try LegacyPreferenceSnapshot(domain: ["unknown": "value", "editorSmartHome": false])
        let report = LegacyPreferenceReport(snapshot: first)
        #expect(report == LegacyPreferenceReport(snapshot: reordered))
        #expect(report.sourceDigest == first.canonicalDigest)
        #expect(try LegacyPreferenceReport(snapshot: LegacyPreferenceSnapshot(domain: [:])).entries.isEmpty)
    }
}
