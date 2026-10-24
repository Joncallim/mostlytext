@testable import AppSettings
import CryptoKit
import Foundation
import Testing

@Suite("Raw editor destination evidence")
struct LegacyEditorDestinationEvidenceTests {
    private func fixture(
        statusBar: Bool? = true,
        smartHome: Bool = false,
        version: Int? = nil
    ) throws -> Data {
        let encoded = try JSONEncoder().encode(EditorSettings(
            showsStatusBar: statusBar ?? true, convertsTabsToSpaces: false,
            smartHome: smartHome, autoIncrementOrderedLists: true
        ))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        if statusBar == nil {
            object.removeValue(forKey: "showsStatusBar")
        }
        if let version {
            object["schemaVersion"] = version
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @Test func absentDomainHasNoInventedPersistedValues() {
        let evidence = LegacyEditorDestinationEvidence.decode(nil)
        #expect(evidence.status == .absent)
        #expect(evidence.rawRevision == "absent")
        #expect(evidence.persisted.isEmpty)
        #expect(evidence.provenAbsent.isEmpty)
    }

    @Test func historicalSchemaKeepsPersistedBooleansAndOnlyDefaultsAdditiveField() throws {
        let raw = try fixture(statusBar: nil)
        let evidence = LegacyEditorDestinationEvidence.decode(raw)
        #expect(evidence.status == .knownCompatible)
        #expect(evidence.persisted == [
            .autoIncrementOrderedLists: true,
            .convertsTabsToSpaces: false,
            .smartHome: false,
        ])
        #expect(evidence.provenAbsent.isEmpty)
    }

    @Test func currentSchemaPreservesExplicitFalseAndDefaultEqualValues() throws {
        let raw = try fixture(version: 1)
        let evidence = LegacyEditorDestinationEvidence.decode(raw)
        #expect(evidence.status == .valid)
        #expect(evidence.persisted[.smartHome] == false)
        #expect(evidence.persisted[.autoIncrementOrderedLists] == true)
        #expect(evidence.provenAbsent.isEmpty)
    }

    @Test func rawRevisionBindsExactBytesAndRepeatDecodeIsIdempotent() throws {
        let raw = try fixture()
        let evidence = LegacyEditorDestinationEvidence.decode(raw)
        let digest = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        #expect(evidence.rawRevision == "sha256:" + digest)
        #expect(LegacyEditorDestinationEvidence.decode(raw) == evidence)
        #expect(LegacyEditorDestinationEvidence.decode(Data(" \n".utf8) + raw).rawRevision !=
            evidence.rawRevision)
    }

    @Test func malformedAndUnknownFutureBytesArePreservedByPureAdmission() {
        let unsupported: [(Data, LegacyEditorDestinationEvidence.Status)] = [
            (Data("broken".utf8), .malformed),
            (Data([0xFF, 0xFE]), .malformed),
            (Data("[]".utf8), .malformed),
            (Data("{\"schemaVersion\":null}".utf8), .malformed),
            (Data("{\"schemaVersion\":2}".utf8), .unknownFuture),
            (Data("{\"smartHome\":true,\"smart\\u0048ome\":false}".utf8), .malformed),
            (Data("{\"caf\\u00e9\":true,\"cafe\\u0301\":false}".utf8), .malformed),
        ]
        for (raw, expected) in unsupported {
            let original = raw
            let evidence = LegacyEditorDestinationEvidence.decode(raw)
            #expect(evidence.status == expected)
            #expect(evidence.persisted.isEmpty)
            #expect(evidence.provenAbsent.isEmpty)
            #expect(raw == original)
        }
    }

    @Test func missingRequiredFieldAndInvalidTypesOrRangesFailClosed() throws {
        let current = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        let corruptions: [[String: Any]] = [
            current.filter { $0.key != "font" },
            current.merging(["smartHome": "false"]) { _, replacement in replacement },
            current.merging(["indentationWidth": 9]) { _, replacement in replacement },
            current.merging(["showsStatusBar": NSNull()]) { _, replacement in replacement },
        ]
        for object in corruptions {
            let raw = try JSONSerialization.data(withJSONObject: object)
            #expect(LegacyEditorDestinationEvidence.decode(raw).status == .malformed)
        }
    }

    @Test func unknownKeysCannotSilentlyBecomeCurrentSchema() throws {
        var object = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        object["futurePreference"] = true
        let raw = try JSONSerialization.data(withJSONObject: object)
        #expect(LegacyEditorDestinationEvidence.decode(raw).status == .unknownFuture)
    }
}
