@testable import FileCore
import Foundation
import Testing

/// #183 F22 — Save As publishes against the destination baseline captured at
/// authorization, so a file another process created or changed in between is
/// never silently overwritten.
@Suite("FileStore Save As destination baseline (#183 F22)")
struct FileStoreSaveAsBaselineTests {
    private func leftovers(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".private-stage-") }
    }

    @Test func baselineDescribesAbsentFilesAndRegularFiles() throws {
        let fixture = try FixtureFile(text: "x")
        let store = FileStore()

        #expect(try store.destinationBaseline(at: fixture.directory.appendingPathComponent("nope.md")) == .absent)
        guard case .revision = try store.destinationBaseline(at: fixture.url) else {
            Issue.record("expected a revision baseline")
            return
        }
    }

    @Test func anAbsentBaselineWritesANewFile() throws {
        let fixture = try FixtureFile()
        _ = try FileStore().write("fresh", to: fixture.url, destinationBaseline: .absent)

        #expect(try FileStore().read(from: fixture.url).content == "fresh")
        #expect(try leftovers(in: fixture.directory).isEmpty)
    }

    @Test func anAbsentBaselineRefusesADestinationThatNowExists() throws {
        let fixture = try FixtureFile(text: "someone else's file")

        #expect(throws: FileStoreError.self) {
            _ = try FileStore().write("ours", to: fixture.url, destinationBaseline: .absent)
        }
        #expect(try FileStore().read(from: fixture.url).content == "someone else's file")
        #expect(try leftovers(in: fixture.directory).isEmpty)
    }

    @Test func anAbsentBaselineLosesARaceToAFileCreatedJustBeforePublication() throws {
        let fixture = try FixtureFile()
        let store = FileStore(afterBaselineVerification: { url in
            try Data("external winner".utf8).write(to: url)
        })

        do {
            _ = try store.write("ours", to: fixture.url, destinationBaseline: .absent)
            Issue.record("expected the exclusive publication to fail")
        } catch FileStoreError.fileChangedDuringRead {
            // expected
        }

        #expect(try FileStore().read(from: fixture.url).content == "external winner")
        #expect(try leftovers(in: fixture.directory).isEmpty)
    }

    @Test func aRevisionBaselineOverwritesAnUnchangedDestination() throws {
        let fixture = try FixtureFile(text: "one")
        let baseline = try FileStore().destinationBaseline(at: fixture.url)

        _ = try FileStore().write("two", to: fixture.url, destinationBaseline: baseline)

        #expect(try FileStore().read(from: fixture.url).content == "two")
    }

    @Test func aRevisionBaselineRefusesADestinationModifiedAfterAuthorization() throws {
        let fixture = try FixtureFile(text: "one")
        let baseline = try FileStore().destinationBaseline(at: fixture.url)
        try Data("changed behind our back".utf8).write(to: fixture.url)

        #expect(throws: FileStoreError.self) {
            _ = try FileStore().write("ours", to: fixture.url, destinationBaseline: baseline)
        }
        #expect(try FileStore().read(from: fixture.url).content == "changed behind our back")
    }

    @Test func aDirectoryDestinationIsRefusedAtBaselineCapture() throws {
        let fixture = try FixtureFile()

        #expect(throws: FileStoreError.self) {
            _ = try FileStore().destinationBaseline(at: fixture.directory)
        }
    }

    // MARK: - Document-level baseline selection

    private func saveAs(_ document: FileDocument, to url: URL) throws -> FileDocument {
        try document.saveAs(url, destinationBaseline: document.saveAsBaseline(for: url))
    }

    @Test func saveAsOntoTheOwnUnchangedFileSucceeds() throws {
        let fixture = try FixtureFile(text: "one")
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")

        _ = try saveAs(document, to: fixture.url)

        #expect(try FileStore().read(from: fixture.url).content == "two")
    }

    @Test func saveAsOntoTheOwnFileKeepsExternalWriterProtectionWhileHealthy() throws {
        let fixture = try FixtureFile(text: "one")
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "ours")
        try Data("external edit".utf8).write(to: fixture.url)

        #expect(throws: FileStoreError.self) { _ = try saveAs(document, to: fixture.url) }
        #expect(try FileStore().read(from: fixture.url).content == "external edit")
    }

    @Test func saveAsOntoTheOwnFileRecreatesItAfterItWasDeleted() throws {
        let fixture = try FixtureFile(text: "one")
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "ours")
        try FileManager.default.removeItem(at: fixture.url)

        _ = try saveAs(document, to: fixture.url)

        #expect(try FileStore().read(from: fixture.url).content == "ours")
    }

    @Test func saveAsOntoAnExternallyChangedOwnFileIsTheUsersExplicitResolution() throws {
        let fixture = try FixtureFile(text: "one")
        let dirty = try FileDocument(fileURL: fixture.url).load().edited(text: "ours")
        try Data("external edit".utf8).write(to: fixture.url)
        let snapshot = try FileStore().readSnapshot(from: fixture.url)
        let document = dirty.reconcilingExternalSnapshot(snapshot).document
        #expect(document.state == .conflict)

        _ = try saveAs(document, to: fixture.url)

        #expect(try FileStore().read(from: fixture.url).content == "ours")
    }

    /// Foundation's replacement already refuses a symbolic-link destination, so
    /// Save As onto one fails exactly as before; the baseline is simply not
    /// imposed on top (`nil` = the pre-existing unconditional path).
    @Test func aSymbolicLinkDestinationGetsNoBaselineSoItsBehaviourIsUnchanged() throws {
        let fixture = try FixtureFile(text: "target")
        let link = fixture.directory.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.url)
        let dangling = fixture.directory.appendingPathComponent("dangling.md")
        try FileManager.default.createSymbolicLink(
            at: dangling,
            withDestinationURL: fixture.directory.appendingPathComponent("missing.md")
        )
        let document = FileDocument(text: "").updatingText("new")

        #expect(try document.saveAsBaseline(for: link) == nil)
        #expect(try document.saveAsBaseline(for: dangling) == nil)
    }

    @Test func aCaseVariantSpellingOfTheOwnFileKeepsTheProtection() throws {
        let fixture = try FixtureFile(text: "one")
        let variant = fixture.directory.appendingPathComponent("DOCUMENT.MD")
        guard FileManager.default.fileExists(atPath: variant.path) else { return } // case-sensitive volume
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "ours")
        try Data("external edit".utf8).write(to: fixture.url)

        #expect(throws: FileStoreError.self) { _ = try saveAs(document, to: variant) }
        #expect(try FileStore().read(from: fixture.url).content == "external edit")
    }

    /// The synthesized `FileRevision ==` includes `url`, so Save As onto a case-only spelling of the document's own
    /// unchanged file (a plain rename of `Notes.md` to `notes.md`) never matched its own baseline and failed.
    @Test func aCaseOnlySaveAsOfTheUnchangedOwnFileSucceeds() throws {
        let fixture = try FixtureFile(text: "one")
        let variant = fixture.directory.appendingPathComponent("DOCUMENT.MD")
        guard FileManager.default.fileExists(atPath: variant.path) else { return } // case-sensitive volume
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "ours")

        _ = try saveAs(document, to: variant)

        #expect(try FileStore().read(from: fixture.url).content == "ours")
    }

    @Test func anUntitledDocumentMayReplaceAnExistingFileItsUserConfirmed() throws {
        let fixture = try FixtureFile(text: "old")
        let document = FileDocument(text: "").updatingText("new")

        _ = try saveAs(document, to: fixture.url)

        #expect(try FileStore().read(from: fixture.url).content == "new")
    }
}
