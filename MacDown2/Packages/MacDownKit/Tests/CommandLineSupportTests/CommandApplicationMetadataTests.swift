@testable import CommandLineSupport
import Darwin
import Foundation
import Testing

struct CommandApplicationMetadataTests {
    @Test(arguments: [0, 1, 65536]) func exactRegularFileBoundariesAreReadUnchanged(count: Int) throws {
        try withRoot { root in
            let url = root.appendingPathComponent("Info.plist")
            let bytes = Data(repeating: 0x41, count: count)
            try bytes.write(to: url)
            #expect(try CommandApplicationMetadata.read(at: url) == bytes)
        }
    }

    @Test func oversizedMetadataIsRefusedBeforeReading() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("Info.plist")
            try Data(repeating: 0x41, count: 65537).write(to: url)
            #expect(throws: EmbeddedCommandFailure.invalidContainer) { try CommandApplicationMetadata.read(at: url) }
        }
    }

    @Test func aFIFOWithoutAnyWriterIsRefusedWithoutWaitingForOne() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("Info.plist")
            try #require(mkfifo(url.path, 0o600) == 0)
            #expect(throws: EmbeddedCommandFailure.invalidContainer) { try CommandApplicationMetadata.read(at: url) }
        }
    }

    @Test func aLeafSymlinkCannotSupplyMetadata() throws {
        try withRoot { root in
            let actual = root.appendingPathComponent("actual.plist")
            let alias = root.appendingPathComponent("Info.plist")
            let bytes = Data("outside metadata".utf8)
            try bytes.write(to: actual)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
            #expect(throws: EmbeddedCommandFailure.invalidContainer) { try CommandApplicationMetadata.read(at: alias) }
            #expect(try Data(contentsOf: actual) == bytes)
        }
    }

    @Test func directoriesAndMissingMetadataAreRefused() throws {
        try withRoot { root in
            for url in [root, root.appendingPathComponent("missing")] {
                #expect(throws: EmbeddedCommandFailure.invalidContainer) { try CommandApplicationMetadata.read(at: url)
                }
            }
        }
    }

    @Test func replacementAfterOpenPreservesBothObjectsAndRefusesStaleBytes() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("Info.plist")
            let moved = root.appendingPathComponent("original.plist")
            try Data("original".utf8).write(to: url)
            #expect(throws: EmbeddedCommandFailure.invalidContainer) {
                try CommandApplicationMetadata.read(at: url) {
                    try FileManager.default.moveItem(at: url, to: moved)
                    try Data("replacement".utf8).write(to: url)
                }
            }
            #expect(try Data(contentsOf: moved) == Data("original".utf8))
            #expect(try Data(contentsOf: url) == Data("replacement".utf8))
        }
    }

    @Test func anInPlaceEditAfterOpenIsRefusedAndLeftUntouched() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("Info.plist")
            try Data("original".utf8).write(to: url)
            #expect(throws: EmbeddedCommandFailure.invalidContainer) {
                try CommandApplicationMetadata.read(at: url) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.write(contentsOf: Data("changed-size".utf8))
                }
            }
            #expect(try Data(contentsOf: url) == Data("changed-size".utf8))
        }
    }

    @Test func successfulAndRejectedReadsReleaseTheirDescriptors() throws {
        try withRoot { root in
            let regular = root.appendingPathComponent("regular")
            let pipe = root.appendingPathComponent("pipe")
            try Data([1]).write(to: regular)
            try #require(mkfifo(pipe.path, 0o600) == 0)
            let baseline = descriptorCount(under: root)
            for _ in 0 ..< 32 {
                #expect(try CommandApplicationMetadata.read(at: regular) == Data([1]))
                #expect(throws: EmbeddedCommandFailure.invalidContainer) {
                    try CommandApplicationMetadata.read(at: pipe)
                }
            }
            #expect(descriptorCount(under: root) == baseline)
        }
    }

    private func descriptorCount(under root: URL) -> Int {
        let prefix = Array((root.resolvingSymlinksInPath().path + "/").utf8)
        return (0 ..< 1024).count { descriptor in
            var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(Int32(descriptor), F_GETPATH, &buffer) == 0 else { return false }
            return buffer.prefix { $0 != 0 }.starts(with: prefix)
        }
    }

    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cli-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
