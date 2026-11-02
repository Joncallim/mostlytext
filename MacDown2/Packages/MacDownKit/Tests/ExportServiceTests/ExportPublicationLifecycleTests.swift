@testable import ExportService
import Foundation
import Testing

struct ExportPublicationLifecycleTests {
    @Test func primaryLeafCannotBeItsCompanionDirectory() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let primary = item.directory.appendingPathComponent("report.assets", isDirectory: false)
        let target = ExportTarget.html(url: primary, mode: .standalone(style: .embedded))
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(), to: target)
        }
        #expect(!FileManager.default.fileExists(atPath: item.assets.path))
    }

    @Test func taskCancellationAtTheCutoffCleansVerifiedScratch() async throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let prepared = try ExportPublicationTestSupport.prepared()
        try Data("old".utf8).write(to: item.primary)
        let task = Task {
            let hooks = ExportPublicationHooks(beforePromotion: { withUnsafeCurrentTask { $0?.cancel() } })
            #expect(throws: CancellationError.self) {
                _ = try ExportFileWriter.writeHTML(prepared, to: item.target, hooks: hooks)
            }
        }
        await task.value
        #expect(try Data(contentsOf: item.primary) == Data("old".utf8))
        let prefix = ExportPublicationRetention.scratchPrefix(for: "report.html")
        #expect(try !FileManager.default.contentsOfDirectory(atPath: item.directory.path)
            .contains { $0.hasPrefix(prefix) })
        _ = try ExportFileWriter.writeHTML(prepared, to: item.target)
    }

    @Test func changedParentCannotPromoteIntoAReplacementDirectory() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let selected = item.directory.appendingPathComponent("selected")
        let detached = item.directory.appendingPathComponent("detached")
        let outside = item.directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let target = selected.appendingPathComponent("report.html")
        try Data("old".utf8).write(to: target)
        var entered = false
        let hooks = ExportPublicationHooks(beforePromotion: {
            do {
                try FileManager.default.moveItem(at: selected, to: detached)
                try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: outside)
                entered = true
            } catch { Issue.record("Could not replace parent: \(error)") }
        })
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(),
                                               to: .html(url: target, mode: .standalone(style: .embedded)),
                                               hooks: hooks)
        }
        #expect(entered)
        #expect(try Data(contentsOf: detached.appendingPathComponent("report.html")) == Data("old".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func selectedParentMustExistBeforePublication() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let parent = item.directory.appendingPathComponent("not-selected")
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(),
                                               to: .html(url: parent.appendingPathComponent("report.html"),
                                                         mode: .standalone(style: .embedded)))
        }
        #expect(!FileManager.default.fileExists(atPath: parent.path))
    }

    @Test func aSymlinkedPrimaryIsRejectedBeforeCreatingCompanions() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let outside = item.directory.appendingPathComponent("authoritative.html")
        try Data("keep".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: item.primary, withDestinationURL: outside)
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(), to: item.target)
        }
        #expect(try Data(contentsOf: outside) == Data("keep".utf8))
        #expect(!FileManager.default.fileExists(atPath: item.assets.path))
    }

    @Test func concurrentPublishersShareTheOpenedParentGate() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let prepared = try ExportPublicationTestSupport.prepared()
        let record = ConcurrentPublicationRecord()
        let group = DispatchGroup()
        for _ in 0 ..< 20 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let hooks = ExportPublicationHooks(beforePromotion: { record.observeOverlap() })
                    _ = try ExportFileWriter.writeHTML(prepared, to: item.target, hooks: hooks)
                } catch { record.failed(error) }
            }
        }
        #expect(group.wait(timeout: .now() + .seconds(30)) == .success)
        #expect(record.maximum == 1)
        #expect(record.failures.isEmpty)
        #expect(try Data(contentsOf: item.primary) == Data(ExportHTMLWriter.companionHTML(from: prepared,
                                                                                          style: .embedded).utf8))
    }
}

private final class ConcurrentPublicationRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var peak = 0
    private var errors: [String] = []
    var maximum: Int {
        lock.withLock { peak }
    }

    var failures: [String] {
        lock.withLock { errors }
    }

    func observeOverlap() {
        lock.withLock { active += 1; peak = max(peak, active) }
        Thread.sleep(forTimeInterval: 0.002)
        lock.withLock { active -= 1 }
    }

    func failed(_ error: Error) {
        lock.withLock { errors.append(String(describing: error)) }
    }
}
