import FileCore
import Foundation
import Testing

struct CommandDocumentPathTests {
    @Test func parentComponentsAreResolvedAfterSymlinkTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lexical = root.appendingPathComponent("lexical")
        let physical = root.appendingPathComponent("physical")
        try FileManager.default.createDirectory(at: lexical, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: physical.appendingPathComponent("child"),
                                                withIntermediateDirectories: true)
        try Data("wrong".utf8).write(to: lexical.appendingPathComponent("document.md"))
        try Data("right".utf8).write(to: physical.appendingPathComponent("document.md"))
        try FileManager.default.createSymbolicLink(at: lexical.appendingPathComponent("link"),
                                                   withDestinationURL: physical.appendingPathComponent("child"))
        let path = lexical.path + "/link/../document.md"
        let resolved = URL(fileURLWithPath: path).resolvingFinalSymlink()
        #expect(try Data(contentsOf: resolved) == Data("right".utf8))
    }
}
