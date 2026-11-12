import Foundation
@testable import QuickLookSource
import Testing

@Suite("Quick Look selected-file open deadline", .serialized)
struct QuickLookSelectedFileOpenerTests {
    @Test func aBlockedOpenReturnsAtTheDeadline() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("mostlytext-ql-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("selected.md")
        try Data("# selected\n".utf8).write(to: file)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let returned = DispatchSemaphore(value: 0)
        defer { release.signal() }

        let pending = Task {
            try await QuickLookSelectedFileOpener.open(file, timeout: .milliseconds(40)) {
                entered.signal()
                _ = release.wait(timeout: .now() + 2)
                defer { returned.signal() }
                return try FileHandle(forReadingFrom: file)
            }
        }
        let didEnter = await waitForSignal(entered)
        #expect(didEnter)
        do {
            _ = try await pending.value
            Issue.record("A blocked selected-file open crossed the reply deadline")
        } catch QuickLookSourceError.openTimedOut {
            // The open thread may still be blocked; the reply has settled.
        }
        release.signal()
        let didReturn = await waitForSignal(returned)
        #expect(didReturn)
    }

    @Test func anOrdinarySelectedFileStillOpensAndRenders() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("mostlytext-ql-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("selected.md")
        try Data("# selected\n".utf8).write(to: file)
        let selected = try await QuickLookSelectedFileOpener.open(file)
        let html = try #require(String(bytes: QuickLookSourceFallback.replyHTML(
            forOpenDescriptor: selected.fileDescriptor
        ), encoding: .utf8))
        #expect(html.contains("# selected"))
    }

    private func waitForSignal(_ semaphore: DispatchSemaphore) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + 1) == .success)
            }
        }
    }
}
