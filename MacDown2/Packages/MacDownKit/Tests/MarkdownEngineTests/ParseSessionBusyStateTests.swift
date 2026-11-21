import Foundation
@testable import MarkdownEngine
import Testing

@MainActor
struct ParseSessionBusyStateTests {
    @Test func supersededDebouncedParseKeepsSessionBusyUntilItDrains() async {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .milliseconds(1))

        session.textDidChange("first")
        await engine.waitUntilStarted(1)
        session.textDidChange("second")
        await engine.waitUntilStarted(2)

        await engine.release(call: 2)
        await Fixtures.wait(timeout: .seconds(5)) {
            await MainActor.run { session.document?.body == "second" }
        }
        #expect(session.document?.body == "second")
        #expect(session.isParsing, "The superseded parser has not returned")

        await engine.release(call: 1)
        await Fixtures.wait(timeout: .seconds(5)) {
            await MainActor.run { !session.isParsing }
        }
        #expect(!session.isParsing)
        #expect(session.document?.body == "second")
    }

    @Test func evictingATabRejectsItsHeldDebouncedParse() async {
        let engine = GatedParseEngine()
        let store = MarkdownParseStore(engine: engine, debounce: .milliseconds(1))
        let session = store.session(for: "tab")
        session.textDidChange("first")
        await engine.waitUntilStarted(1)

        store.evict("tab")
        #expect(store.existingSession(for: "tab") == nil)
        await engine.release(call: 1)
        await Fixtures.wait(timeout: .seconds(5)) {
            await MainActor.run { !session.isParsing }
        }
        #expect(!session.isParsing)
        #expect(session.document == nil)
        #expect(session.publishedText == nil)
        #expect(session.completedParseCount == 0)
    }

    @Test func evictingAllTabsRejectsAHeldDebouncedParse() async {
        let engine = GatedParseEngine()
        let store = MarkdownParseStore(engine: engine, debounce: .milliseconds(1))
        let session = store.session(for: "tab")
        session.textDidChange("first")
        await engine.waitUntilStarted(1)

        store.evictAll()
        #expect(store.existingSession(for: "tab") == nil)
        await engine.release(call: 1)
        await Fixtures.wait(timeout: .seconds(5)) {
            await MainActor.run { !session.isParsing }
        }
        #expect(!session.isParsing)
        #expect(session.document == nil)
        #expect(session.publishedText == nil)
        #expect(session.completedParseCount == 0)
    }

    /// An older immediate parse completing while a newer one is still
    /// outstanding must not report the session idle.
    @Test func olderImmediateCompletionKeepsSessionBusyWhileNewerParseIsOutstanding() async {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))

        let first = Task { await session.parseNow("first") }
        await engine.waitUntilStarted(1)
        let second = Task { await session.parseNow("second") }
        await engine.waitUntilStarted(2)

        await engine.release(call: 1)
        _ = await first.value
        #expect(session.isParsing, "the second immediate parse is still outstanding")

        await engine.release(call: 2)
        _ = await second.value
        #expect(!session.isParsing, "the session is idle once every parse has finished")
        #expect(session.document?.body == "second")
    }

    /// The newer parse finishing first leaves the superseded one running;
    /// the session stays busy until it is also done and then settles idle
    /// (the superseded completion must not leave it stuck busy).
    @Test func newerImmediateFinishingFirstStillSettlesIdle() async {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))

        let first = Task { await session.parseNow("first") }
        await engine.waitUntilStarted(1)
        let second = Task { await session.parseNow("second") }
        await engine.waitUntilStarted(2)

        await engine.release(call: 2)
        _ = await second.value
        #expect(session.isParsing, "the superseded parse has not returned yet")

        await engine.release(call: 1)
        _ = await first.value
        #expect(!session.isParsing)
        #expect(session.document?.body == "second", "the superseded result must not overwrite the newer one")
    }

    /// `cancelPending` while an immediate parse is in flight must not leave
    /// the busy flag stuck once that parse returns.
    @Test func cancelPendingDuringImmediateParseSettlesIdle() async {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))

        let parse = Task { await session.parseNow("only") }
        await engine.waitUntilStarted(1)
        session.cancelPending()
        await engine.release(call: 1)
        _ = await parse.value
        #expect(!session.isParsing)
    }

    /// A caller that leaves while parsing is suspended must not publish the
    /// returned document after cancellation, even when the parser itself
    /// completes successfully.
    @Test func cancelledImmediateParseDoesNotPublishAStaleDocument() async {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))

        let parse = Task { await session.parseNow("stale") }
        await engine.waitUntilStarted(1)
        parse.cancel()
        await engine.release(call: 1)

        #expect(await parse.value == nil)
        #expect(session.document == nil)
        #expect(session.publishedText == nil)
    }
}
