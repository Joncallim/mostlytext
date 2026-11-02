@testable import ExportService
import Foundation
import Testing

/// Resource resolution: root containment, reference decoding, deduplication and
/// the export budgets.
struct ExportResourceResolverTests {
    private func resolver(
        root: URL?,
        fatal: Bool = false,
        budget: ExportResourceBudget = .standard
    ) throws -> ExportResourceResolver {
        let access = try root.map { try ExportResourceAccess(openingDirectory: $0) }
        return ExportResourceResolver(resourceAccess: access, unresolvedIsFatal: fatal, budget: budget)
    }

    @Test func resolvesAnImageInsideTheDocumentFolder() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "images/a.png", in: directory, bytes: Data([0x89, 0x50]))

        let subject = try resolver(root: directory)
        #expect(try subject.disposition(for: "images/a.png", isImage: true) != .keep)
        #expect(subject.diagnostics.isEmpty)
    }

    @Test func refusesToReadOutsideTheDocumentFolder() throws {
        let base = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        // A real, readable file that the document has no business embedding.
        try ExportTestSupport.writeFixture(named: "secret.png", in: base, bytes: Data([0x89, 0x50]))
        let documentDirectory = base.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)

        let subject = try resolver(root: documentDirectory)
        #expect(try subject.disposition(for: "../secret.png", isImage: true) == .keep)
        #expect(subject.diagnostics.contains { $0.message.contains("outside the document's folder") })
    }

    @Test func decodesPercentEncodedFilenames() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "my image.png", in: directory, bytes: Data([0x89, 0x50]))

        // Editors write spaces as %20; the file on disk still has a space.
        let subject = try resolver(root: directory)
        #expect(try subject.disposition(for: "my%20image.png", isImage: true) != .keep)
        #expect(subject.diagnostics.isEmpty)
    }

    @Test func repeatedReferencesShareOneResourceAndOneDiagnostic() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "a.png", in: directory, bytes: Data([0x89, 0x50]))

        let subject = try resolver(root: directory)
        let first = try subject.disposition(for: "a.png", isImage: true)
        let second = try subject.disposition(for: "a.png", isImage: true)
        #expect(first == second)
        #expect(subject.frozenManifest().resources.count == 1)

        _ = try subject.disposition(for: "missing.png", isImage: true)
        _ = try subject.disposition(for: "missing.png", isImage: true)
        #expect(subject.diagnostics.count == 1)
    }

    @Test func rejectsAResourceLargerThanTheSingleFileBudget() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "big.png", in: directory, bytes: Data(repeating: 0x41, count: 64))

        let tiny = ExportResourceBudget(
            maxSourceUTF8Bytes: 1024,
            maxResourceCount: 8,
            maxSingleResourceBytes: 16,
            maxAggregateResourceBytes: 1024,
            maxDerivedFragmentCount: 8,
            maxAggregateDerivedHTMLBytes: 1024,
            maxPreparedHTMLUTF8Bytes: 1024
        )
        let subject = try resolver(root: directory, budget: tiny)
        #expect(try subject.disposition(for: "big.png", isImage: true) == .keep)
        #expect(subject.diagnostics.contains { $0.message.contains("per-file export limit") })
        #expect(subject.frozenManifest().resources.isEmpty)
    }

    @Test func rejectsResourcesPastTheCountBudget() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0 ..< 3 {
            try ExportTestSupport.writeFixture(
                named: "img\(index).png",
                in: directory,
                bytes: Data([0x89, UInt8(index)])
            )
        }

        let capped = ExportResourceBudget(
            maxSourceUTF8Bytes: 1024,
            maxResourceCount: 2,
            maxSingleResourceBytes: 1024,
            maxAggregateResourceBytes: 1024,
            maxDerivedFragmentCount: 8,
            maxAggregateDerivedHTMLBytes: 1024,
            maxPreparedHTMLUTF8Bytes: 1024
        )
        let subject = try resolver(root: directory, budget: capped)
        for index in 0 ..< 3 {
            _ = try subject.disposition(for: "img\(index).png", isImage: true)
        }
        #expect(subject.frozenManifest().resources.count == 2)
        #expect(subject.diagnostics.contains { $0.message.contains("2-resource limit") })
    }

    @Test func aNonImageFileInTheDocumentFolderIsNeverPackagedAsAnImage() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: ".env", in: directory, bytes: Data("SECRET=hunter2".utf8))
        try ExportTestSupport.writeFixture(named: "notes.txt", in: directory, bytes: Data("private".utf8))
        try ExportTestSupport.writeFixture(named: "noextension", in: directory, bytes: Data("private".utf8))
        let subject = try resolver(root: directory, fatal: false)

        for reference in [".env", "notes.txt", "noextension"] {
            #expect(try subject.disposition(for: reference, isImage: true) == .keep)
        }

        #expect(subject.frozenManifest().resources.isEmpty)
        #expect(subject.diagnostics.count == 3)
        #expect(subject.diagnostics.allSatisfy { $0.message.contains("not an image file") })
    }

    @Test func unresolvedIsAWarningOrAnErrorByTarget() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let lenient = try resolver(root: directory, fatal: false)
        _ = try lenient.disposition(for: "missing.png", isImage: true)
        #expect(lenient.diagnostics.allSatisfy { $0.severity == .warning })

        let strict = try resolver(root: directory, fatal: true)
        _ = try strict.disposition(for: "missing.png", isImage: true)
        #expect(strict.diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test func navigationLinksAndFragmentsAreNeverPackaged() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let subject = try resolver(root: directory, fatal: true)
        #expect(try subject.disposition(for: "https://example.com", isImage: false) == .keep)
        #expect(try subject.disposition(for: "#anchor", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.isEmpty)
    }

    @Test func blankedSchemesAreReported() throws {
        // A neutralised link must not just silently lose its target.
        let subject = try resolver(root: nil, fatal: true)
        #expect(try subject.disposition(for: "javascript:alert(1)", isImage: false) == .blank)
        #expect(try subject.disposition(for: "data:text/html;base64,PHNjcmlwdD4=", isImage: true) == .blank)
        #expect(subject.diagnostics.count == 2)
        #expect(subject.diagnostics.allSatisfy { $0.severity == .warning })
    }

    @Test func inlineRasterImagesAreKeptAndOtherDataImagesStayBlanked() throws {
        let subject = try resolver(root: nil, fatal: true)
        #expect(try subject.disposition(for: "data:image/png;base64,iVBORw0KGgo=", isImage: true) == .keep)
        #expect(try subject.disposition(for: "data:image/jpeg;base64,/9j/4AAQ", isImage: true) == .keep)
        #expect(try subject.disposition(for: "data:image/svg+xml;base64,PHN2Zz4=", isImage: true) == .blank)
        #expect(try subject.disposition(for: "data:image/png;base64,AA\"onerror=x", isImage: true) == .blank)
        #expect(try subject.disposition(for: "data:image/png;base64,AAAA", isImage: false) == .blank)
    }

    @Test func rejectsAReferenceThatIsActuallyADirectory() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("images"),
            withIntermediateDirectories: true
        )

        let subject = try resolver(root: directory, fatal: true)
        #expect(try subject.disposition(for: "images", isImage: true) == .keep)
        #expect(subject.diagnostics.contains { $0.severity == .error })
        #expect(subject.frozenManifest().resources.isEmpty)
    }

    @Test func resolvesASymlinkToARegularFileInsideTheRoot() throws {
        // A symlink is not itself a directory/device/socket, and its resolved
        // target is still inside the root, so it must read like any other file.
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try ExportTestSupport.writeFixture(named: "real.png", in: directory, bytes: Data([0x89, 0x50]))
        let link = directory.appendingPathComponent("linked.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let subject = try resolver(root: directory)
        #expect(try subject.disposition(for: "linked.png", isImage: true) != .keep)
        #expect(subject.diagnostics.isEmpty)
        #expect(subject.frozenManifest().resources.count == 1)
    }
}
