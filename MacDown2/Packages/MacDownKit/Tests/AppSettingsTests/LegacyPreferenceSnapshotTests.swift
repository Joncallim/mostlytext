@testable import AppSettings
import Foundation
import Testing

@Suite("LegacyPreferenceSnapshot")
struct LegacyPreferenceSnapshotTests {
    @Test func snapshotsOnlyTheSuppliedDomainAndKeepsValueKinds() throws {
        let domain: [String: Any] = [
            "enabled": true,
            "count": 1,
            "label": "原稿",
            "payload": Data([0, 255]),
            "date": Date(timeIntervalSince1970: 123),
            "nested": ["items": ["one", 2]],
        ]
        let snapshot = try LegacyPreferenceSnapshot(domain: domain)

        #expect(snapshot.values["enabled"] == .boolean(true))
        #expect(snapshot.values["label"] == .string("原稿"))
        #expect(snapshot.values["payload"] == .data(Data([0, 255])))
        #expect(snapshot.values["date"] == .date(123))
        let expectedItems: [LegacyPreferenceValue] = [.string("one"), .number(type: "q", value: "2")]
        #expect(snapshot.values["nested"] == .dictionary(["items": .array(expectedItems)]))
        #expect(snapshot.values["count"] != snapshot.values["enabled"])
        #expect(snapshot.canonicalDigest.count == 64)
    }

    @Test func digestIsStableAcrossDictionaryOrderAndChangesWithAValue() throws {
        let first = try LegacyPreferenceSnapshot(domain: ["z": "last", "a": 1])
        let reordered = try LegacyPreferenceSnapshot(domain: ["a": 1, "z": "last"])
        let changed = try LegacyPreferenceSnapshot(domain: ["a": 2, "z": "last"])
        #expect(first.canonicalDigest == reordered.canonicalDigest)
        #expect(first.canonicalDigest != changed.canonicalDigest)
    }

    @Test func rejectsOversizedAndUnsupportedValuesBeforeAnyImport() throws {
        #expect(throws: LegacyPreferenceSnapshotError.stringTooLong) {
            try LegacyPreferenceSnapshot(domain: ["text": String(repeating: "x", count: 4097)])
        }
        #expect(throws: LegacyPreferenceSnapshotError.tooLarge) {
            try LegacyPreferenceSnapshot(domain: ["bytes": Data(count: LegacyPreferenceSnapshot.maximumBytes)])
        }
        #expect(throws: LegacyPreferenceSnapshotError.tooManyEntries) {
            let many = Array(repeating: 1, count: LegacyPreferenceSnapshot.maximumEntries)
            _ = try LegacyPreferenceSnapshot(domain: ["items": many])
        }
        #expect(throws: LegacyPreferenceSnapshotError.invalidNumber) {
            try LegacyPreferenceSnapshot(domain: ["number": Double.infinity])
        }
        #expect(throws: LegacyPreferenceSnapshotError.unsupportedValue) {
            try LegacyPreferenceSnapshot(domain: ["null": NSNull()])
        }
        var deep: Any = "leaf"
        for _ in 0 ... LegacyPreferenceSnapshot.maximumDepth {
            deep = [deep]
        }
        #expect(throws: LegacyPreferenceSnapshotError.tooDeep) {
            try LegacyPreferenceSnapshot(domain: ["nested": deep])
        }
    }

    @Test func constructingSnapshotDoesNotReadOrWriteAUserDefaultsDomain() throws {
        let name = "legacy-snapshot-fixture-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("not supplied", forKey: "outside")
        let before = defaults.persistentDomain(forName: name)

        let snapshot = try LegacyPreferenceSnapshot(domain: ["inside": "supplied"])

        #expect(snapshot.values == ["inside": .string("supplied")])
        #expect((defaults.persistentDomain(forName: name) as NSDictionary?)?.isEqual(to: before ?? [:]) == true)
    }
}
