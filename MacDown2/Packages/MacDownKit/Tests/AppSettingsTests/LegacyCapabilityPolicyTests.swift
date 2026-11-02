import AppSettings
import Foundation
import Testing

@Suite("Explicit legacy renderer and update policies")
struct LegacyCapabilityPolicyTests {
    @Test(arguments: [true, false])
    func rendererFlagsExplainCurrentSemanticsWithoutCreatingDestinations(value: Bool) throws {
        let keys = [
            "htmlMathJax", "htmlMathJaxInlineDollar", "htmlGraphviz", "htmlMermaid", "htmlRendersTOC",
        ]
        let snapshot = try LegacyPreferenceSnapshot(domain: Dictionary(uniqueKeysWithValues: keys.map { ($0, value) }))
        let report = LegacyPreferenceReport(snapshot: snapshot)
        let policies = report.entries.compactMap { entry -> LegacyPreferenceReport.CapabilityPolicy? in
            guard case let .currentCapabilityPolicy(policy, legacyEnabled) = entry.disposition,
                  legacyEnabled == value else { return nil }
            return policy
        }
        #expect(Set(policies) == Set(LegacyPreferenceReport.CapabilityPolicy.allCases))
        #expect(LegacyImportPlan(source: snapshot, destination: .decode(nil)).entries.isEmpty)
    }

    @Test(arguments: [true, false])
    func updaterFlagNeverBecomesAFeedKeyOrAutomaticChannel(value: Bool) throws {
        let snapshot = try LegacyPreferenceSnapshot(domain: [
            "updateIncludesPreReleases": value,
            "SUFeedURL": "https://example.invalid",
            "SUPublicEDKey": "not-imported",
        ])
        let entries = Dictionary(uniqueKeysWithValues: LegacyPreferenceReport(snapshot: snapshot).entries.map {
            ($0.key, $0.disposition)
        })
        #expect(entries["updateIncludesPreReleases"] == .requiresFreshUpdateConsent(legacyIncludedPrereleases: value))
        #expect(entries["SUFeedURL"] == .unknown && entries["SUPublicEDKey"] == .unknown)
        #expect(LegacyImportPlan(source: snapshot, destination: .decode(nil)).entries.isEmpty)
    }

    @Test func numericAndStringLookalikesRemainInvalid() throws {
        let snapshot = try LegacyPreferenceSnapshot(domain: [
            "htmlMathJax": 1, "htmlGraphviz": "true",
            "htmlMermaid": 0, "htmlRendersTOC": "false",
            "htmlMathJaxInlineDollar": 1,
            "updateIncludesPreReleases": "true",
        ])
        #expect(LegacyPreferenceReport(snapshot: snapshot).entries.allSatisfy { $0.disposition == .invalid })
    }
}
