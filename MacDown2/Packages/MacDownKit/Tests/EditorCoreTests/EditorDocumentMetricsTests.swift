import AppKit
@testable import EditorCore
import FileCore
import Foundation
import Testing

/// #183 F16 — selection-only changes cause zero whole-document metric scans.
@MainActor
@Suite("EditorDocumentMetrics")
struct EditorDocumentMetricsTests {
    private func mounted(_ text: String) -> (EditorTextSystem, NSWindow) {
        let system = EditingAssistIntegrationSupport.makeSystem(text: text)
        return (system, EditingAssistIntegrationSupport.mountInWindow(system))
    }

    private func updated(_ system: EditorTextSystem) async -> EditorDocumentMetrics? {
        system.requestDocumentMetrics()
        await system.metricsStore.settle()
        return system.metricsStore.metrics(for: system.contentRevision)
    }

    @Test func metricsDescribeTheDocument() {
        let metrics = EditorDocumentMetrics(of: "one two\r\nthree")
        #expect(metrics.characterCount == 13)
        #expect(metrics.wordCount == 3)
        #expect(metrics.lineEndings.uniformEnding == .crlf)
    }

    @Test func selectionOnlyChangesNeverRescanTheDocument() async {
        let (system, window) = mounted("alpha beta gamma")
        defer { window.orderOut(nil) }
        _ = await updated(system)
        let baseline = system.metricsStore.computationCount

        for location in 0 ... 10 {
            system.selectedRange = NSRange(location: location, length: 0)
            system.requestDocumentMetrics()
        }
        system.selectedRange = NSRange(location: 2, length: 5)
        system.requestDocumentMetrics()

        #expect(system.metricsStore.computationCount == baseline)
    }

    @Test func aContentChangeRecomputesExactlyOnce() async {
        let (system, window) = mounted("alpha")
        defer { window.orderOut(nil) }
        _ = await updated(system)
        let baseline = system.metricsStore.computationCount

        system.textView.insertText(" beta", replacementRange: NSRange(location: 5, length: 0))
        let after = await updated(system)
        system.requestDocumentMetrics()

        #expect(after?.wordCount == 2)
        #expect(after?.characterCount == 10)
        #expect(system.metricsStore.computationCount == baseline + 1)
    }

    @Test func aWholeDocumentReplacementInvalidatesTheCache() async {
        let (system, window) = mounted("alpha")
        defer { window.orderOut(nil) }
        _ = await updated(system)

        system.replaceTextFromExternal(
            "one\r\ntwo\r\nthree",
            preserving: system.viewportSnapshot(),
            clearUndo: true
        )

        let metrics = await updated(system)
        #expect(metrics?.wordCount == 3)
        #expect(metrics?.lineEndings.uniformEnding == .crlf)
    }

    @Test func aSameLengthEditStillInvalidates() async {
        let (system, window) = mounted("a b")
        defer { window.orderOut(nil) }
        _ = await updated(system)

        system.textView.insertText("-", replacementRange: NSRange(location: 1, length: 1))

        let metrics = await updated(system)
        #expect(metrics?.wordCount == 2)
        #expect(metrics?.characterCount == 3)
    }

    @Test func sameRevisionDoesNotCopyOrRescanTheSource() async {
        let store = EditorDocumentMetricsStore()
        var snapshots = 0
        store.request(revision: 4, length: 5) {
            snapshots += 1
            return "alpha"
        }
        await store.settle()
        store.request(revision: 4, length: 5) {
            snapshots += 1
            return "wrong"
        }
        #expect(snapshots == 1)
        #expect(store.computationCount == 1)
        #expect(store.metrics(for: 4)?.wordCount == 1)
    }

    @Test func lateOldResultCannotReplaceCurrentMetrics() async {
        let gate = MetricsComputeGate()
        let store = EditorDocumentMetricsStore(compute: { text, _ in await gate.compute(text) })
        store.request(revision: 1, length: 1) { "a" }
        await gate.waitUntilStarted("a")
        store.request(revision: 2, length: 3) { "b c" }
        #expect(store.metrics(for: 2) == nil)
        await gate.waitUntilStarted("b c")
        await gate.finish("b c")
        await store.settle()
        #expect(store.metrics(for: 2)?.wordCount == 2)
        await gate.finish("a")
        await store.settleRetired()
        #expect(store.metrics(for: 1) == nil)
        #expect(store.metrics(for: 2)?.wordCount == 2)
        #expect(store.computationCount == 1)
    }

    @Test func cancelledWordEnumerationStopsBeforeTheWholeDocument() {
        let cancellation = EditorMetricsCancellation()
        cancellation.cancel()
        let text = String(repeating: "alpha ", count: 10000)
        let metrics = EditorDocumentMetrics(of: text, stopIf: cancellation.isCancelled)
        #expect(metrics.wordCount == 0)
    }
}

private actor MetricsComputeGate {
    private var pending: [String: CheckedContinuation<EditorDocumentMetrics, Never>] = [:]
    private var startWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func compute(_ text: String) async -> EditorDocumentMetrics {
        await withCheckedContinuation { continuation in
            pending[text] = continuation
            for waiter in startWaiters.removeValue(forKey: text) ?? [] {
                waiter.resume()
            }
        }
    }

    func waitUntilStarted(_ text: String) async {
        if pending[text] != nil {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters[text, default: []].append(continuation)
        }
    }

    func finish(_ text: String) {
        pending.removeValue(forKey: text)?.resume(returning: EditorDocumentMetrics(of: text))
    }
}
