import Darwin
import ExportService
import Foundation
import Testing

@Suite(.serialized)
struct ExportPrintScratchTests {
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
