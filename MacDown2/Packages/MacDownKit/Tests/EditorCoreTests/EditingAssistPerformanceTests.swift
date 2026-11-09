import AppKit
@testable import EditorCore
import Foundation
import Testing

/// E10 performance evidence (§17). The existing `EditorPerformanceTests.keystroke()`
/// `<50 ms` gate stays untouched; these are additive Release measurements.
@MainActor
@Suite("Editing assists — performance")
struct EditingAssistPerformanceTests {
    private let viewportBounds = NSRect(x: 0, y: 0, width: 800, height: 1000)

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000.0 + Double(components.attoseconds) / 1e15
    }

    private func makeSystem(configuration: EditingAssistConfiguration) -> EditorTextSystem {
        var editorConfiguration = EditorConfiguration.default
        editorConfiguration.editingAssists = configuration
        return EditorTextSystem(
            identity: UUID().uuidString,
            initialText: Fixtures.markdown(targetByteCount: 1_000_000),
            configuration: editorConfiguration
        )
    }

    /// A caret near the end of a representative line of the 1 MB fixture.
    private func representativeCaret(in text: NSString) -> Int {
        min(text.length - 2, max(0, text.length - 200))
    }

    @Test("no-op assist decision on a 1 MB document stays local")
    func noOpDecisionOn1MB() {
        let text = Fixtures.markdown(targetByteCount: 1_000_000) as NSString
        let caret = representativeCaret(in: text)

        // Prime the engine once so any lazy one-time work is excluded.
        _ = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "a"),
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: .plainText
        )

        let duration = ContinuousClock().measure {
            // Ordinary alphanumeric replacement: must inspect only the local
            // line and immediate neighbors — no whole-document copy/scan.
            for _ in 0 ..< 100 {
                let outcome = MarkdownEditingAssistEngine.outcome(
                    for: .replacement(range: NSRange(location: caret, length: 0), string: "a"),
                    text: text,
                    selection: NSRange(location: caret, length: 0),
                    configuration: .markdownDefault,
                    profile: .plainText
                )
                #expect(outcome == .passthrough)
            }
        }
        let perDecisionMilliseconds = milliseconds(duration) / 100
        // Headroom target is <5 ms per decision; the hard ceiling is generous
        // against cross-runner variance while still proving locality.
        #expect(perDecisionMilliseconds < 25, "no-op decision took \(perDecisionMilliseconds) ms")
    }

    @Test("handled assist through the adapter on a 1 MB document stays within the keystroke budget")
    func handledAssistOn1MB() throws {
        let system = makeSystem(configuration: .markdownDefault)
        system.textView.frame = viewportBounds

        // Keep the handled case on a list item even when the fixture's final
        // block changes as the requested document size changes.
        let source = try #require(system.assistTextSource)
        let lastListItem = source.range(of: "- List item ", options: .backwards)
        try #require(lastListItem.location != NSNotFound)
        let lineBreak = source.range(
            of: "\n", range: NSRange(location: lastListItem.location, length: source.length - lastListItem.location)
        )
        try #require(lineBreak.location != NSNotFound)
        let item = source.substring(with: NSRange(location: lastListItem.location,
                                                  length: lineBreak.location - lastListItem.location))
        try #require(item.hasSuffix("-c"))
        system.selectedRange = NSRange(location: lineBreak.location, length: 0)

        let duration = ContinuousClock().measure {
            let outcome = MarkdownEditingAssistEngine.outcome(
                for: .insertNewline,
                text: source,
                selection: system.selectedRange,
                configuration: .markdownDefault,
                profile: .plainText
            )
            #expect(system.applyAssistOutcome(outcome))
        }
        let durationMilliseconds = milliseconds(duration)
        #expect(durationMilliseconds < 50, "handled assist took \(durationMilliseconds) ms (budget 50 ms)")
    }

    @Test("incremental E10 overhead is recorded against the disabled baseline")
    func incrementalOverheadVsBaseline() {
        let text = Fixtures.markdown(targetByteCount: 1_000_000) as NSString
        let caret = representativeCaret(in: text)

        // Baseline: assists disabled (the engine still runs — one guard).
        _ = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "a"),
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .disabled,
            profile: .plainText
        )
        let baseline = ContinuousClock().measure {
            for _ in 0 ..< 100 {
                _ = MarkdownEditingAssistEngine.outcome(
                    for: .replacement(range: NSRange(location: caret, length: 0), string: "a"),
                    text: text,
                    selection: NSRange(location: caret, length: 0),
                    configuration: .disabled,
                    profile: .plainText
                )
            }
        }

        _ = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "a"),
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: .plainText
        )
        let assisted = ContinuousClock().measure {
            for _ in 0 ..< 100 {
                _ = MarkdownEditingAssistEngine.outcome(
                    for: .replacement(range: NSRange(location: caret, length: 0), string: "a"),
                    text: text,
                    selection: NSRange(location: caret, length: 0),
                    configuration: .markdownDefault,
                    profile: .plainText
                )
            }
        }

        // Recorded for the PR; the hard gate is the shared 50 ms budget.
        let baselineMs = milliseconds(baseline) / 100
        let assistedMs = milliseconds(assisted) / 100
        #expect(assistedMs < 25, "assisted decision took \(assistedMs) ms vs baseline \(baselineMs) ms")
        print("E10 overhead evidence: disabled baseline \(baselineMs) ms/decision, assisted \(assistedMs) ms/decision")
    }

    /// The smart Home decision must scale with the current line only, and must
    /// not bridge each scanned unit through a temporary Swift `String`. A
    /// per-unit `substring` bridge made a 2 MB whitespace-only line cost ~244
    /// ms per keypress in Debug (~680 ms in Release); the direct unit scan is
    /// ~85 ms in Debug and ~5 ms in Release. The gate catches the regression
    /// in the modes the performance contract runs in (Debug CI + Release
    /// evidence). Under TSan the instrumentation adds a further ~2.5x to the
    /// *new* scan and closes the gap to the old implementation's Debug cost,
    /// so the absolute budget is skipped there: TSan is a race detector, and
    /// the sanitizer's own injection mechanism is the only reliable signal.
    @Test("smart Home decision on a 2 MB whitespace-only line stays within budget")
    func smartHomeOnHugeWhitespaceLineStaysLocal() {
        let text = String(repeating: " ", count: 2_000_000) as NSString
        let duration = ContinuousClock().measure {
            let outcome = MarkdownEditingAssistEngine.outcome(
                for: .smartHome,
                text: text,
                selection: NSRange(location: text.length, length: 0),
                configuration: .markdownDefault,
                profile: .plainText
            )
            #expect(outcome == .selection(NSRange(location: 0, length: 0)))
        }
        let durationMilliseconds = milliseconds(duration)
        // TSan links its runtime into the test process on Darwin; probing the
        // symbol is the reliable signal regardless of the injection mechanism
        // (SwiftPM does not set DYLD_INSERT_LIBRARIES for sanitizer runs).
        let underSanitizer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "__tsan_init") != nil
        #expect(
            underSanitizer || durationMilliseconds < 200,
            "smart Home decision took \(durationMilliseconds) ms (budget 200 ms)"
        )
    }

    /// Return on a plain single-line document is a passthrough decision: it
    /// must not materialize or scan the whole line (which is the whole
    /// document in a single-line file) before concluding no construct exists.
    @Test("Return on a plain 2 MB single line passes through without scanning the line")
    func newlineOnHugePlainLineStaysLocal() {
        let text = String(repeating: "a", count: 2_000_000) as NSString
        let duration = ContinuousClock().measure {
            let outcome = MarkdownEditingAssistEngine.outcome(
                for: .insertNewline,
                text: text,
                selection: NSRange(location: text.length, length: 0),
                configuration: .markdownDefault,
                profile: .plainText
            )
            #expect(outcome == .passthrough)
        }
        let durationMilliseconds = milliseconds(duration)
        #expect(durationMilliseconds < 200, "newline decision took \(durationMilliseconds) ms (budget 200 ms)")
    }
}
