import Darwin
@testable import ExportService
import Foundation
import Testing

@Suite(.serialized)
struct ExportPrintScratchTests {
    @Test func symlinkedTemporaryBaseReportsTheOriginalOpenError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("target")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(symlink(target.path, alias.path) == 0)
        let descriptor = Darwin.open(alias.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor < 0 else {
            _ = close(descriptor)
            Issue.record("A symlinked print base unexpectedly opened")
            return
        }
        let expectedCode = errno

        do {
            _ = try ExportPrintScratch(in: alias)
            Issue.record("A symlinked print base must be refused")
        } catch {
            let description = try #require((error as? LocalizedError)?.errorDescription)
            #expect(description.contains("POSIX \(expectedCode)"))
            #expect(!description.contains(alias.path))
        }
    }

    @Test func unsafeTemporaryBaseRefusesWithoutLeakingItsPath() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(chmod(base.path, 0o755) == 0)

        do {
            _ = try ExportPrintScratch(in: base)
            Issue.record("A group-readable print base must be refused")
        } catch {
            let description = try #require((error as? LocalizedError)?.errorDescription)
            #expect(!description.isEmpty)
            #expect(!description.contains(base.path))
        }
    }

    @Test func missingSandboxTemporaryDirectoryIsCreatedBeforePrinting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let base = root.appendingPathComponent("Data/tmp")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!FileManager.default.fileExists(atPath: base.path))
        let scratch = try ExportPrintScratch(in: base)
        #expect(FileManager.default.fileExists(atPath: base.path))
        #expect(try scratch.read(maxBytes: 1024) == nil)
        try scratch.retire()
    }

    @Test func missingPrinterOutputCanFallBackWithoutPublicScratch() throws {
        let scratch = try ExportPrintScratch()
        let directory = scratch.url.deletingLastPathComponent()
        #expect(try scratch.read(maxBytes: 1024) == nil)
        try scratch.retire()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func printerFileStaysInAnOwnedPrivateDirectory() throws {
        let scratch = try ExportPrintScratch()
        let directory = scratch.url.deletingLastPathComponent()
        defer { try? scratch.retire() }
        var info = stat()
        #expect(lstat(directory.path, &info) == 0)
        #expect(info.st_uid == geteuid())
        #expect(info.st_mode & 0o7777 == 0o700)
        #expect(scratch.url.lastPathComponent == "print.pdf")

        let printed = Data("%PDF-private-scratch".utf8)
        try printed.write(to: scratch.url, options: .atomic)
        #expect(try scratch.read(maxBytes: 1024) == printed)
        try scratch.retire()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func substitutedSymlinkCannotBecomePrintBytesOrBeRetired() throws {
        let scratch = try ExportPrintScratch()
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = Data("external".utf8)
        try original.write(to: target)
        defer {
            _ = unlink(scratch.url.path)
            try? scratch.retire()
            try? FileManager.default.removeItem(at: target)
        }
        #expect(symlink(target.path, scratch.url.path) == 0)
        #expect(throws: ExportError.self) { try scratch.read(maxBytes: 1024) }
        #expect(throws: ExportError.self) { try scratch.retire() }
        #expect(try Data(contentsOf: target) == original)
    }
}
