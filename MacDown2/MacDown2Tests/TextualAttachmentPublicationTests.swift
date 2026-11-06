import Foundation
import SwiftUI
import Testing
@testable import Textual

@MainActor
@Suite("Textual attachment publication ownership", .serialized, .timeLimit(.minutes(1)))
struct TextualAttachmentPublicationTests {
    private typealias Model = WithAttachments<Text>.Model

    @Test func plainSourceReplacesThePreviouslyResolvedImageSource() async throws {
        let model = Model()
        let previous = try imageSource("previous")
        await resolve(model, previous, using: RejectedAttachmentLoader())
        try #require(model.resolvedAttributedString != nil)
        let current = AttributedString("current e\u{301} 😀\r\nplain text")
        await resolve(model, current, using: RejectedAttachmentLoader())
        #expect(matches(model, current), "Plain source must replace the prior resolved image source")
    }

    @Test func cancelledOlderReadCannotPublishOverNewerSource() async throws {
        let model = Model()
        let gate = AttachmentReadGate()
        defer { gate.release() }
        let previous = try imageSource("previous")
        let older = Task { await resolve(model, previous, using: HeldRejectedAttachmentLoader(gate: gate)) }
        try #require(await gate.waitForEntry(), "The real model must enter the held attachment callback")
        older.cancel()
        let current = try imageSource("current e\u{301} 😀")
        await resolve(model, current, using: RejectedAttachmentLoader())
        try #require(matches(model, current))
        gate.release()
        await older.value
        #expect(matches(model, current), "Cancelled attachment completion must not replace newer source")
    }

    @Test func olderUncancelledReadCannotPublishOverNewerSource() async throws {
        let model = Model()
        let gate = AttachmentReadGate()
        defer { gate.release() }
        let previous = try imageSource("previous")
        let older = Task { await resolve(model, previous, using: HeldRejectedAttachmentLoader(gate: gate)) }
        try #require(await gate.waitForEntry(), "The real model must enter the held attachment callback")
        let current = try imageSource("current e\u{301} 😀")
        await resolve(model, current, using: RejectedAttachmentLoader())
        try #require(matches(model, current))
        gate.release()
        await older.value
        #expect(matches(model, current), "Older attachment completion must retain the latest request's source")
    }

    @Test func requestCancelledBeforeEntryCannotReplaceCurrentContent() async throws {
        let model = Model()
        let current = try imageSource("current e\u{301} 😀")
        await resolve(model, current, using: RejectedAttachmentLoader())
        try #require(matches(model, current))
        let gate = AttachmentReadGate()
        defer { gate.release() }
        let previous = try imageSource("previous")
        let cancelled = Task {
            await gate.hold()
            #expect(Task.isCancelled)
            await resolve(model, previous, using: RejectedAttachmentLoader())
        }
        try #require(await gate.waitForEntry())
        cancelled.cancel()
        gate.release()
        await cancelled.value
        #expect(matches(model, current), "Already cancelled requests must not clear or replace current content")
    }

    private func imageSource(_ label: String) throws -> AttributedString {
        let source = try AttributedString(markdown: "![\(label)](image.png)")
        try #require(source.runs.contains { $0.imageURL != nil })
        return source
    }

    private func resolve(_ model: Model, _ source: AttributedString, using loader: some AttachmentLoader) async {
        await model.resolveAttachments(
            in: source, imageAttachmentLoader: loader, emojiAttachmentLoader: loader,
            environment: ColorEnvironmentValues(colorScheme: .light, colorSchemeContrast: .standard)
        )
    }

    private func matches(_ model: Model, _ source: AttributedString) -> Bool {
        let displayed = model.resolvedAttributedString ?? source
        return String(displayed.characters).utf8.elementsEqual(String(source.characters).utf8)
    }
}

private enum AttachmentProbeError: Error {
    case rejected
}

private struct RejectedAttachmentLoader: AttachmentLoader {
    func attachment(for _: URL, text _: String, environment _: ColorEnvironmentValues) async throws -> AnyAttachment {
        throw AttachmentProbeError.rejected
    }
}

private struct HeldRejectedAttachmentLoader: AttachmentLoader {
    let gate: AttachmentReadGate

    func attachment(for _: URL, text _: String, environment _: ColorEnvironmentValues) async throws -> AnyAttachment {
        await gate.hold()
        throw AttachmentProbeError.rejected
    }
}

/// The held callback deliberately ignores cancellation until released. Every test releases and drains it.
private final class AttachmentReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let entered: AsyncStream<Void>
    private let signalEntry: AsyncStream<Void>.Continuation
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    init() {
        (entered, signalEntry) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    func hold() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if released {
                    continuation.resume()
                } else {
                    waiter = continuation
                }
            }
            signalEntry.yield(())
        }
    }

    func release() {
        let continuation = lock.withLock {
            released = true
            let current = waiter
            waiter = nil
            return current
        }
        continuation?.resume()
    }

    func waitForEntry() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = self.entered.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
