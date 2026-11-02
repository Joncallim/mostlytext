@testable import ExportService
import Foundation
import LocalResourceAccess
import Testing

struct ExportResourceWorkTests {
    @Test func pathSpellingsReuseTheFrozenImageAfterItsNameDisappears() throws {
        let root = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ExportTestSupport.writeFixture(named: "a b.png", in: root, bytes: Data([1, 2, 3]))
        let subject = try resolver(root, attempts: 1, bytes: 3)
        let first = try subject.disposition(for: "a%20b.png?first", isImage: true)
        try FileManager.default.removeItem(at: root.appendingPathComponent("a b.png"))
        for path in ["./a%20b.png#second", "a b.png?third", "folder/../a%20b.png"] {
            #expect(try subject.disposition(for: path, isImage: true) == first)
            #expect(subject.packagedIdentity(for: path) != nil)
        }
        #expect(subject.frozenManifest().resources.count == 1)
        #expect(subject.frozenManifest().referenceMap.count == 4)
        #expect(subject.diagnostics.isEmpty)
    }

    @Test func firstMissingPathRemainsUnresolvedAcrossQueryVariants() throws {
        let root = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let subject = try resolver(root, attempts: 1, bytes: 4)
        #expect(try subject.disposition(for: "a.png?missing", isImage: true) == .keep)
        try ExportTestSupport.writeFixture(named: "a.png", in: root, bytes: Data([1]))
        #expect(try subject.disposition(for: "a.png?later", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.isEmpty)
        #expect(subject.diagnostics.count == 2)
    }

    @Test func canonicallyEquivalentFilenamesKeepSeparateByteKeys() throws {
        let root = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // A missing spelling followed by a created canonical equivalent also
        // discriminates on normalization-insensitive macOS filesystems.
        let subject = try resolver(root, attempts: 2, bytes: 4)
        #expect(try subject.disposition(for: "caf\u{E9}.png", isImage: true) == .keep)
        try ExportTestSupport.writeFixture(named: "cafe\u{301}.png", in: root, bytes: Data([1]))
        #expect(try subject.disposition(for: "cafe\u{301}.png", isImage: true) != .keep)
        #expect(subject.frozenManifest().resources.count == 1)
    }

    @Test func byteDistinctReferencesKeepBothFrozenPayloadsAndAuditEntries() throws {
        let root = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let composed = "caf\u{E9}.png"
        let decomposed = "cafe\u{301}.png"
        try ExportTestSupport.writeFixture(named: composed, in: root, bytes: Data([1]))
        let subject = try resolver(root, attempts: 2, bytes: 2)
        let first = try subject.disposition(for: composed, isImage: true)
        try ExportTestSupport.writeFixture(named: decomposed, in: root, bytes: Data([2]))
        let second = try subject.disposition(for: decomposed, isImage: true)
        #expect(first != .keep && second != .keep && first != second)
        #expect(subject.packagedIdentity(for: composed) != subject.packagedIdentity(for: decomposed))
        let manifest = subject.frozenManifest()
        #expect(manifest.resources.count == 2)
        #expect(manifest.referenceMappings.count == 2)
        #expect(manifest.referenceMappings.contains { $0.authoredReference.utf8.elementsEqual(composed.utf8) })
        #expect(manifest.referenceMappings.contains { $0.authoredReference.utf8.elementsEqual(decomposed.utf8) })
        #expect(subject.diagnostics.isEmpty)
    }

    @Test func identicalHardLinksStillConsumeActualReadBytes() throws {
        let root = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("a.png")
        try ExportTestSupport.writeFixture(named: "a.png", in: root, bytes: Data([1, 2, 3, 4]))
        for name in ["b.png", "c.png"] {
            try FileManager.default.linkItem(at: original, to: root.appendingPathComponent(name))
        }
        let subject = try resolver(root, attempts: 8, bytes: 8)
        #expect(try subject.disposition(for: "a.png", isImage: true) != .keep)
        #expect(try subject.disposition(for: "b.png", isImage: true) != .keep)
        #expect(try subject.disposition(for: "c.png", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.count == 1)
        #expect(subject.frozenManifest().referenceMap.count == 2)
        #expect(subject.diagnostics.count == 1)
        #expect(subject.diagnostics.first?.message.contains("read-work limit") == true)
    }

    @Test func rejectedNonImageBytesConsumeWorkBeforePayloadAdmission() throws {
        let root = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ExportTestSupport.writeFixture(named: "a.txt", in: root, bytes: Data([1, 2, 3, 4]))
        try ExportTestSupport.writeFixture(named: "a.png", in: root, bytes: Data([1]))
        let subject = try resolver(root, attempts: 8, bytes: 4)
        #expect(try subject.disposition(for: "a.txt", isImage: true) == .keep)
        #expect(try subject.disposition(for: "a.png", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.isEmpty)
        #expect(subject.diagnostics.last?.message.contains("read-work limit") == true)
    }

    @Test(arguments: [false, true]) func missingAttemptsHaveAFiniteDestinationCorrectLimit(fatal: Bool) throws {
        let root = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let subject = try resolver(root, attempts: 2, bytes: 8, fatal: fatal)
        _ = try subject.disposition(for: "missing1.png", isImage: true)
        _ = try subject.disposition(for: "missing2.png", isImage: true)
        try ExportTestSupport.writeFixture(named: "present.png", in: root, bytes: Data([1]))
        #expect(try subject.disposition(for: "present.png", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.isEmpty)
        #expect(subject.diagnostics.count == 3)
        #expect(subject.diagnostics.last?.message.contains("read-work limit") == true)
        #expect(subject.diagnostics.allSatisfy { $0.severity == (fatal ? .error : .warning) })
    }

    private func resolver(_ root: URL, attempts: Int, bytes: Int,
                          fatal: Bool = false) throws -> ExportResourceResolver {
        try ExportResourceResolver(
            resourceAccess: ExportResourceAccess(openingDirectory: root), unresolvedIsFatal: fatal,
            accounting: ResourceReadAccounting(maxAttempts: attempts, maxBytes: bytes)
        )
    }
}
