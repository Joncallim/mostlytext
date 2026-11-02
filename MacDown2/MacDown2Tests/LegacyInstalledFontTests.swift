import AppKit
import AppSettings
@testable import MacDown2
import Testing

@Suite("Installed legacy font resolution")
@MainActor
struct LegacyInstalledFontTests {
    @Test func ordinaryInstalledFaceRoundTripsWithoutSubstitution() throws {
        let regular = try #require(NSFont(name: "Menlo-Regular", size: 14))
        let source = try LegacyPreferenceSnapshot(domain: [
            "editorBaseFontInfo": ["name": regular.fontName, "size": 14],
        ])
        let entry = try #require(LegacyPreferenceReport(snapshot: source).entries.first)
        guard case let .requiresExactInstalledFont(request) = entry.disposition else {
            Issue.record("Missing font request"); return
        }
        let value = try #require(LegacyImportEnvironment.resolveFont(request))
        let ordinary = NSFontManager.shared.font(withFamily: value.descriptor.familyName,
                                                 traits: [], weight: 5, size: value.descriptor.size)
        #expect(ordinary?.fontName == regular.fontName)
        #expect(ordinary?.pointSize == 14)
    }

    @Test func missingFaceIsNotOfferedAsAnotherFamily() throws {
        let source = try LegacyPreferenceSnapshot(domain: [
            "editorBaseFontInfo": ["name": "MostlyText-Missing-\(UUID().uuidString)", "size": 14],
        ])
        let entry = try #require(LegacyPreferenceReport(snapshot: source).entries.first)
        guard case let .requiresExactInstalledFont(request) = entry.disposition else { return }
        #expect(LegacyImportEnvironment.resolveFont(request) == nil)
    }
}
