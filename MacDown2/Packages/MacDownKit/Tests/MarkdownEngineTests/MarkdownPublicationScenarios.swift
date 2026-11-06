import Foundation
import MarkdownEngine

struct MarkdownPublicationCheck {
    let passed: Bool
    let message: String
}

/// These held completions exercise the actual session independently of engine cancellation cooperation.
@MainActor
enum MarkdownPublicationScenarios {
    static func cancelledImmediate() async -> [MarkdownPublicationCheck] {
        var checks: [MarkdownPublicationCheck] = []
        for seeded in [false, true] {
            let engine = GatedParseEngine()
            let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))
            if seeded {
                let seed = Task { await session.parseNow("accepted") }
                await engine.waitUntilStarted(1)
                await engine.release(call: 1)
                _ = await seed.value
            }
            let call = seeded ? 2 : 1
            let count = seeded ? 1 : 0
            let previous = session.document
            let previousText = session.publishedText
            let pending = Task { await session.parseNow("cancelled") }
            await engine.waitUntilStarted(call)
            session.cancelPending()
            checks.append(.init(passed: session.isParsing, message: "Cancellation retains the physical busy count"))
            await engine.release(call: call)
            let returned = await pending.value
            checks += [
                .init(passed: returned == nil, message: "A cancelled generation returns no accepted document"),
                .init(passed: session.document == previous, message: "Cancellation preserves the accepted document"),
                .init(passed: session.publishedText == previousText, message: "Cancellation preserves accepted source"),
                .init(passed: session.completedParseCount == count, message: "A cancelled generation is not counted"),
                .init(passed: !session.isParsing, message: "The session settles idle after the physical return"),
            ]
        }
        return checks
    }

    static func supersededImmediate() async -> [MarkdownPublicationCheck] {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))
        let older = Task { await session.parseNow("older") }
        await engine.waitUntilStarted(1)
        let newer = Task { await session.parseNow("newer") }
        await engine.waitUntilStarted(2)
        await engine.release(call: 1)
        let returned = await older.value
        var checks: [MarkdownPublicationCheck] = [
            .init(passed: returned == nil, message: "A superseded immediate generation returns no accepted document"),
            .init(passed: session.document == nil, message: "Older work cannot publish before newer held work"),
            .init(passed: session.publishedText == nil, message: "Older work cannot publish stale source"),
            .init(passed: session.completedParseCount == 0, message: "Superseded work is not counted"),
            .init(passed: session.isParsing, message: "The newer physical operation keeps the session busy"),
        ]
        await engine.release(call: 2)
        let accepted = await newer.value
        checks += [
            .init(passed: accepted?.body == "newer", message: "The current immediate caller still receives its result"),
            .init(passed: session.document?.body == "newer", message: "The current immediate generation publishes"),
            .init(passed: session.publishedText == "newer", message: "Accepted source belongs to current work"),
            .init(passed: session.completedParseCount == 1, message: "Only the accepted generation is counted"),
            .init(passed: !session.isParsing, message: "Every physical immediate operation has returned"),
        ]
        return checks
    }

    static func supersededByEdit() async -> [MarkdownPublicationCheck] {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))
        let older = Task { await session.parseNow("older") }
        await engine.waitUntilStarted(1)
        session.textDidChange("edited")
        await engine.release(call: 1)
        let returned = await older.value
        var checks: [MarkdownPublicationCheck] = [
            .init(passed: returned == nil, message: "A newer scheduled edit rejects the earlier immediate result"),
            .init(passed: session.document == nil, message: "A debounced edit forbids stale document publication"),
            .init(passed: session.publishedText == nil, message: "A debounced edit forbids stale source publication"),
            .init(passed: session.completedParseCount == 0, message: "Work superseded by an edit is not counted"),
            .init(passed: session.isParsing, message: "Earlier cleanup cannot clear the newer pending edit"),
        ]
        // The next immediate request legitimately supersedes the debounce; do not wait for a wall-clock deadline.
        let newest = Task { await session.parseNow("current edited") }
        await engine.waitUntilStarted(2)
        await engine.release(call: 2)
        let accepted = await newest.value
        checks += [
            .init(passed: accepted?.body == "current edited", message: "A subsequent current request succeeds"),
            .init(
                passed: session.document?.body == "current edited",
                message: "Current document replaces the rejected result"
            ),
            .init(passed: session.publishedText == "current edited", message: "Current accepted source remains exact"),
            .init(
                passed: session.completedParseCount == 1,
                message: "Only the current request increments publication count"
            ),
            .init(passed: !session.isParsing, message: "Current completion settles physical and pending busy state"),
        ]
        return checks
    }
}
