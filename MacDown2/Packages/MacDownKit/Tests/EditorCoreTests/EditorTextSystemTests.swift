import AppKit
@testable import EditorCore
import Testing

@MainActor
@Suite("EditorTextSystem")
struct EditorTextSystemTests {
    private func makeSystem(text: String = "") -> EditorTextSystem {
        EditorTextSystem(
            identity: UUID().uuidString,
            initialText: text,
            configuration: .default
        )
    }

    @Test("initial text is set")
    func initialText() {
        let system = makeSystem(text: "hello")
        #expect(system.text == "hello")
    }

    @Test("setText replaces content")
    func setTextReplaces() {
        let system = makeSystem(text: "hello")
        system.setText("world")
        #expect(system.text == "world")
    }

    @Test("external replacement clamps UTF-16 selection and clears undo")
    func externalReplacementPreservesViewportSafely() {
        let system = makeSystem(text: "prefix \u{1F680} suffix")
        system.selectedRange = NSRange(location: 8, length: 20)
        system.undoManager.registerUndo(withTarget: system) { _ in }
        #expect(system.undoManager.canUndo)

        system.replaceTextFromExternal(
            "\u{65E5}\u{672C}\u{8A9E}",
            preserving: system.viewportSnapshot(),
            clearUndo: true
        )

        #expect(system.text == "\u{65E5}\u{672C}\u{8A9E}")
        #expect(system.selectedRange == NSRange(location: 3, length: 0))
        #expect(!system.undoManager.canUndo)
        #expect(!system.isPerformingProgrammaticTextUpdate)
    }

    @Test("external replacement retains a pending scroll offset before mounting")
    func externalReplacementRetainsPendingScrollOffset() {
        let system = makeSystem(text: "old")
        system.scrollOffset = 42
        let snapshot = system.viewportSnapshot()
        #expect(snapshot.topVisibleUTF16Offset == nil)
        #expect(snapshot.topVisibleFragmentOffset == nil)

        system.replaceTextFromExternal("new", preserving: snapshot, clearUndo: false)

        #expect(system.scrollOffset == 42)
    }

    /// This is the highest deterministic UI-facing seam: a real mounted
    /// AppKit text system and scroll view, without accessibility APIs that do
    /// not expose an NSTextView's UTF-16 selection or viewport offset.
    @Test("mounted editor preserves selection and scroll across external replacement")
    func mountedExternalReplacementPreservesSelectionAndScroll() {
        let text = Array(repeating: "A line that makes the editor scroll.", count: 160)
            .joined(separator: "\n")
        let system = makeSystem(text: text)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        system.textView.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
        system.syncFrameHeightToContent()
        system.selectedRange = NSRange(location: 24, length: 4)
        system.scrollOffset = 72
        let viewport = system.viewportSnapshot()

        system.replaceTextFromExternal(text + "\nDisk replacement", preserving: viewport, clearUndo: true)
        system.syncFrameHeightToContent()
        system.applyPendingScrollOffset()

        #expect(system.selectedRange == viewport.selectedRange)
        #expect(abs(system.scrollOffset - viewport.scrollOffset) < 0.5)
    }

    @Test("mounted external replacement preserves an off-screen selection and viewport")
    func mountedExternalReplacementPreservesOffScreenViewport() async throws {
        let text = (1 ... 180)
            .map { "LINE_\(String(format: "%03d", $0)) selection and scroll preservation marker" }
            .joined(separator: "\n")
        let system = makeSystem(text: text)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        system.textView.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
        system.syncFrameHeightToContent()

        let selectedLine = (text as NSString).range(of: "LINE_120")
        system.selectedRange = selectedLine
        let topLocation = (text as NSString).range(of: "LINE_070").location
        let topFrame = try #require(system.layoutFragmentFrame(atUTF16Location: topLocation))
        system.scrollOffset = topFrame.minY + system.textView.textContainerInset.height
        let viewport = system.viewportSnapshot()
        #expect(viewport.scrollOffset > 0)
        #expect(viewport.topVisibleUTF16Offset == topLocation)
        system.replaceTextFromExternal(
            text.replacingOccurrences(
                of: "LINE_180 selection and scroll preservation marker",
                with: "LINE_180 refreshed from disk"
            ),
            preserving: viewport,
            clearUndo: true
        )
        try? await Task.sleep(for: .milliseconds(150))

        #expect(system.selectedRange == selectedLine)
        #expect(system.topVisibleUTF16Offset == viewport.topVisibleUTF16Offset)
        #expect(system.pendingExternalViewport == nil)
        #expect(system.pendingExternalViewportRevision == nil)
    }

    @Test("external replacement preserves the visible row within a wrapped source line")
    func wrappedExternalReplacementPreservesIntraFragmentOffset() throws {
        let text = (1 ... 100)
            .map { "LINE_\(String(format: "%03d", $0)) " + String(repeating: "wrapped source text ", count: 8) }
            .joined(separator: "\n")
        let system = makeSystem(text: text)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 180))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        system.textView.frame = NSRect(x: 0, y: 0, width: 220, height: 180)
        system.syncFrameHeightToContent()
        let selectedRange = (text as NSString).range(of: "LINE_080")
        system.selectedRange = selectedRange
        let sourceLocation = (text as NSString).range(of: "LINE_040").location
        let frame = try #require(system.layoutFragmentFrame(atUTF16Location: sourceLocation))
        #expect(frame.height > 40)
        system.scrollOffset = frame.minY + system.textView.textContainerInset.height + frame.height * 0.65
        let viewport = system.viewportSnapshot()
        #expect(viewport.topVisibleUTF16Offset == sourceLocation)
        #expect(try #require(viewport.topVisibleFragmentOffset) > 20)
        system.replaceTextFromExternal(
            text.replacingOccurrences(of: "LINE_100", with: "DISK_100"),
            preserving: viewport,
            clearUndo: true
        )
        system.frameSyncTask?.cancel()
        // Drive both deferred restore passes without a timing dependency.
        for _ in 0 ..< 2 {
            system.syncFrameHeightToContent()
            #expect(system.applyPendingExternalViewport())
            #expect(abs(system.scrollOffset - viewport.scrollOffset) < 0.5)
        }
        #expect(system.selectedRange == selectedRange)
        #expect(system.topVisibleUTF16Offset == viewport.topVisibleUTF16Offset)
    }

    @Test("later content changes discard a reload viewport before scrolling", arguments: [false, true])
    func laterContentChangesDiscardPendingReloadViewport(modelReplacement: Bool) {
        let text = Array(repeating: "A line that makes the editor scroll.", count: 160)
            .joined(separator: "\n")
        let system = makeSystem(text: text)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        system.textView.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
        system.syncFrameHeightToContent()
        system.scrollOffset = 1000
        let viewport = system.viewportSnapshot()
        system.replaceTextFromExternal(text, preserving: viewport, clearUndo: true)
        // Drive the deferred seam directly so this tests invalidation without
        // depending on the timing of the frame-sync task.
        system.frameSyncTask?.cancel()
        if modelReplacement {
            system.setText(text + "\nNew model content")
        } else {
            system.noteTextEdit()
        }
        system.syncFrameHeightToContent()
        // Change the live clip origin directly, retaining the reload's raw
        // pending offset so the fallback must also reject stale state.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 40))
        let currentOffset = system.scrollOffset
        #expect(currentOffset != viewport.scrollOffset)

        #expect(!system.applyPendingExternalViewport())
        system.applyPendingScrollOffset()

        #expect(system.scrollOffset == currentOffset)
        #expect(system.pendingExternalViewport == nil)
        #expect(system.pendingExternalViewportRevision == nil)
        #expect(system.pendingScrollOffset == nil)
    }

    @Test("selectedRange can be read and written")
    func selectedRangeRoundTrip() {
        let system = makeSystem(text: "hello world")
        system.selectedRange = NSRange(location: 2, length: 3)
        #expect(system.selectedRange == NSRange(location: 2, length: 3))
    }

    @Test("each text system has an independent undo manager")
    func undoIsPerSystem() {
        let systemA = makeSystem(text: "A")
        let systemB = makeSystem(text: "B")

        #expect(systemA.undoManager !== systemB.undoManager)
    }

    @Test("store caches and reuses systems by identity")
    func storeReusesByIdentity() {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString

        let first = store.system(for: identity, initialText: "first", configuration: .default)
        let second = store.system(for: identity, initialText: "second", configuration: .default)

        #expect(first === second)
        #expect(first.text == "first")
    }

    @Test("evict removes the cached system")
    func evictRemovesSystem() {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString

        weak var weakSystem: EditorTextSystem?
        autoreleasepool {
            let system = store.system(for: identity, initialText: "", configuration: .default)
            weakSystem = system
            store.evict(identity)
        }

        #expect(store.liveIdentities.isEmpty)
        #expect(weakSystem == nil)
    }

    @Test("store tracks live identities")
    func liveIdentities() {
        let store = EditorTextSystemStore()
        let idA = UUID().uuidString
        let idB = UUID().uuidString

        _ = store.system(for: idA, initialText: "", configuration: .default)
        _ = store.system(for: idB, initialText: "", configuration: .default)

        #expect(store.liveIdentities == Set([idA, idB]))
    }

    @Test("undo stack survives evict-less re-fetch from store")
    func undoSurvivesReFetch() {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString

        let first = store.system(for: identity, initialText: "hello", configuration: .default)
        // Register a trivial undo action directly; AppKit's text view does not
        // register undos in a headless test environment.
        first.undoManager.registerUndo(withTarget: first) { _ in }
        #expect(first.undoManager.canUndo)

        let second = store.system(for: identity, initialText: "", configuration: .default)
        #expect(second === first)
        #expect(second.undoManager.canUndo)
    }
}
