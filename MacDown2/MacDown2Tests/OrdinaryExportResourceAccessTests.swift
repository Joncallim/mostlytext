import ExportService
import FileCore
import Foundation
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes

@MainActor
@Suite("Ordinary export resource access")
struct OrdinaryExportResourceAccessTests {
    @Test func resourceDirectoryOpenRunsAwayFromTheMainThread() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ordinary-export-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let observed = ResourceOpenThreadObservation()
        let document = FileDocument(
            fileURL: directory.appendingPathComponent("source.md"), text: "# Frozen source"
        )

        let snapshot = await OrdinaryExportSnapshot(
            document: document, theme: BundledThemes.light, parseOptions: .default,
            openResourceAccess: { root in
                observed.recordCurrentThread()
                return try? ExportResourceAccess(openingDirectory: root)
            }
        )

        #expect(observed.openedOffMainThread)
        #expect(snapshot.resourceAccess != nil)
        #expect(snapshot.text == "# Frozen source")
        #expect(snapshot.documentURL == document.fileURL)
    }
}

private final class ResourceOpenThreadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var openedOffMain = false

    func recordCurrentThread() {
        lock.withLock { openedOffMain = !Thread.isMainThread }
    }

    var openedOffMainThread: Bool {
        lock.withLock { openedOffMain }
    }
}
