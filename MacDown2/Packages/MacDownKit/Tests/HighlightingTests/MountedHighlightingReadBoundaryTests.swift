import AppKit
import Foundation
@testable import Highlighting
import Testing

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct MountedHighlightingReadBoundaryTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MOSTLYTEXT_HIGHLIGHT_READ_DIAGNOSTIC"] == "1"))
    func replacementWhileAnInjectedLanguageRequestIsHeldMatchesFreshHighlighting() async throws {
        let gate = InjectedLanguageGate()
        defer { gate.release() }
        let registry = GrammarRegistry(beforeInjectedLanguageResolution: gate.observe)
        let initial = StallFixtures.markdown(utf8Bytes: 48 * 1024)
        let editor = HighlightedEditor(text: initial, registry: registry)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        let scroll = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scroll.hasVerticalScroller = true
        scroll.documentView = editor.textView
        window.contentView = scroll
        if !NSRunningApplication.current.isFinishedLaunching {
            NSApplication.shared.finishLaunching()
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor.textView)
        defer { window.orderOut(nil); window.close() }
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(1), timeout: .seconds(30)))
        let pending = "```javascript\nlet pending = 'before';\n```\n\n" + initial
        editor.textView.insertText(
            pending,
            replacementRange: NSRange(location: 0, length: editor.textView.string.utf16.count)
        )
        let entered = await gate.waitForEntry()
        try #require(entered, "The real parser must hold a background JavaScript request: \(gate.events)")
        editor.textView.insertText("# Shrink 😀\r\n", replacementRange:
            NSRange(location: 0, length: editor.textView.string.utf16.count))
        let final = "```javascript\r\nlet current = 'after 😀';\r\n```\r\n\r\n"
            + StallFixtures.markdown(utf8Bytes: 72 * 1024)
        editor.textView.insertText(final, replacementRange:
            NSRange(location: 0, length: editor.textView.string.utf16.count))
        gate.release()
        let fresh = HighlightedEditor(text: final)
        try #require(await fresh.waitUntilQuiet(quietPeriod: .seconds(1), timeout: .seconds(30)))
        let expected = fresh.renderedRuns()
        try #require(!expected.isEmpty)
        #expect(await editor.waitUntilRuns(equal: expected, timeout: .seconds(30)) != nil)
        #expect(editor.textView.string.utf8.elementsEqual(final.utf8))
        #expect(gate.events.contains("background-held"))
        #expect(!gate.events.contains("hold-timed-out"))
        print("HIGHLIGHT_READ_CONTROL events=\(gate.events) sourceBytes=\(final.utf8.count)")
    }
}

private final class InjectedLanguageGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var armed = true
    private var entered = false
    private var cancelledWait = false
    private var observer: CheckedContinuation<Bool, Never>?
    private var recorded: [String] = []

    var events: [String] {
        lock.withLock { recorded }
    }

    func observe(_ language: String) {
        guard language == "javascript" else { return }
        guard !Thread.isMainThread else {
            lock.withLock {
                if recorded.count < 32 {
                    recorded.append("main-lookup")
                }
            }
            return
        }
        let shouldHold = lock.withLock {
            guard armed else { return false }
            armed = false
            entered = true
            recorded.append("background-held")
            let waiting = observer
            observer = nil
            waiting?.resume(returning: true)
            return true
        }
        guard shouldHold else { return }
        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            lock.withLock { recorded.append("hold-timed-out") }
        }
    }

    func release() {
        lock.withLock {
            armed = false
            if !recorded.contains("released") {
                recorded.append("released")
            }
        }
        semaphore.signal()
    }

    func waitForEntry() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.waitForSignal() }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let value = await group.next() ?? false
            group.cancelAll()
            return value
        }
    }

    private func waitForSignal() async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    if entered {
                        continuation.resume(returning: true)
                    } else if cancelledWait || Task.isCancelled {
                        continuation.resume(returning: false)
                    } else {
                        observer = continuation
                    }
                }
            }
        } onCancel: {
            self.lock.withLock {
                self.cancelledWait = true
                self.observer?.resume(returning: false)
                self.observer = nil
            }
        }
    }
}
