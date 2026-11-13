@testable import FileCore
import Foundation
import Testing

/// #183 F02 — canonically equivalent but scalar-distinct text is *different*
/// authored text wherever identity decides persistence or dirtiness. U+212B
/// ANGSTROM SIGN and U+00C5 LATIN CAPITAL LETTER A WITH RING ABOVE have equal
/// UTF-16 length, compare equal as Swift Strings, and differ in bytes.
@Suite("Exact text identity (#183 F02)")
struct ExactTextIdentityTests {
    private let angstrom = "\u{212B}"
    private let aRing = "\u{00C5}"

    @Test func theFixturePairIsCanonicallyEqualButScalarDistinct() {
        #expect(angstrom == aRing)
        #expect(angstrom.utf16.count == aRing.utf16.count)
        #expect(!angstrom.isExactlyEqual(to: aRing))
        #expect("é".isExactlyEqual(to: "é"))
        #expect(!"\u{00E9}".isExactlyEqual(to: "e\u{0301}"))
    }

    @Test func literalEqualityMatchesAnIndependentUTF16OracleAcrossNativeAndBridgedText() {
        let samples = [
            "", "\0", "a\0b", "a", "A", "\r", "\n", "\r\n",
            "\u{212B}", "\u{00C5}", "\u{00E9}", "e\u{0301}",
            "👩🏽‍💻", "🇸🇬", "字", "\u{FE0F}",
        ]
        let values = samples.flatMap { sample in [sample, (sample as NSString) as String] }
        for left in values {
            for right in values {
                #expect(left.isExactlyEqual(to: right) == left.utf16.elementsEqual(right.utf16))
            }
        }
    }

    @Test func largeBridgedTextChecksTheFinalUnitAndEmbeddedNul() {
        let prefix = String(repeating: "a\0👩🏽‍💻", count: 40000)
        let source = (prefix + "END") as NSString as String
        #expect(source.isExactlyEqual(to: prefix + "END"))
        #expect(!source.isExactlyEqual(to: prefix + "ENX"))
        #expect(!source.isExactlyEqual(to: prefix + "END\0"))
    }

    @Test func updatingTextAdoptsAScalarDistinctReplacement() {
        let document = FileDocument(text: angstrom)

        let edited = document.updatingText(aRing)

        #expect(Array(edited.text.unicodeScalars) == Array(aRing.unicodeScalars))
        #expect(edited.state == .dirty)
    }

    @Test func updatingTextWithIdenticalScalarsIsStillANoOp() {
        let document = FileDocument(text: angstrom)

        #expect(document.updatingText(angstrom).mutationGeneration == document.mutationGeneration)
    }

    @Test func aDescendantWithScalarDistinctTextStaysDirtyAfterASaveOfTheOther() throws {
        let fixture = try FixtureFile(text: "seed")
        let saved = try FileDocument(fileURL: fixture.url).load().edited(text: angstrom).save()

        let descendant = FileDocument(fileURL: fixture.url, text: "").updatingText(aRing)
            .rebindingSavedDestination(from: saved)

        #expect(descendant.state == .dirty)
        #expect(Array(descendant.text.unicodeScalars) == Array(aRing.unicodeScalars))
    }

    @Test func anExternalSnapshotWithScalarDistinctTextIsNotTreatedAsTheSameText() throws {
        let fixture = try FixtureFile()
        _ = try FileStore().write(aRing, to: fixture.url)
        let snapshot = try FileStore().readSnapshot(from: fixture.url)
        let document = FileDocument(fileURL: fixture.url, text: angstrom)

        let reconciliation = document.reconcilingExternalSnapshot(snapshot)

        #expect(Array(reconciliation.document.text.unicodeScalars) == Array(aRing.unicodeScalars))
    }
}
