import AppKit
import FileCore
import SwiftUI

final class EditorAttachmentScrollView: NSScrollView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.onWindowChange?()
        }
    }
}

/// A SwiftUI representable that wraps a TextKit 2-backed `NSTextView`.
///
/// The view uses a cached ``EditorTextSystem`` keyed by `identity` so that the
/// underlying text view, undo manager, selection, and scroll position persist
/// across SwiftUI rebuilds (e.g., tab switches).
public struct EditorView: NSViewRepresentable {
    @Binding private var text: String
    private let identity: String
    private let configuration: EditorConfiguration
    private let store: EditorTextSystemStore
    private let onSelectionChange: ((NSRange) -> Void)?
    private let onScrollChange: ((Int) -> Void)?
    private let onLayoutChange: (() -> Void)?

    /// Creates an editor view.
    /// - Parameters:
    ///   - text: Two-way binding to the document text. Writes flow back on
    ///     every editing transaction.
    ///   - identity: A stable identity for the document (typically a tab UUID).
    ///   - configuration: Editor appearance and behavior preferences.
    ///   - store: The cache that owns per-tab text systems.
    ///   - onSelectionChange: Optional callback invoked when the selection changes.
    ///   - onScrollChange: Optional callback invoked with the UTF-16 offset of
    ///     the character at the top of the visible rect whenever the editor
    ///     scrolls (see ``EditorTextSystem/topVisibleUTF16Offset``).
    public init(
        text: Binding<String>,
        identity: String,
        configuration: EditorConfiguration,
        store: EditorTextSystemStore,
        onSelectionChange: ((NSRange) -> Void)? = nil,
        onScrollChange: ((Int) -> Void)? = nil,
        onLayoutChange: (() -> Void)? = nil
    ) {
        _text = text
        self.identity = identity
        self.configuration = configuration
        self.store = store
        self.onSelectionChange = onSelectionChange
        self.onScrollChange = onScrollChange
        self.onLayoutChange = onLayoutChange
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let system = store.system(
            for: identity,
            initialText: text,
            configuration: configuration
        )

        let scrollView = EditorAttachmentScrollView(frame: .zero)
        scrollView.documentView = system.textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !configuration.wrapsLines
        scrollView.autohidesScrollers = configuration.wrapsLines
        scrollView.borderType = .noBorder
        system.scrollView = scrollView

        let gutterView = EditorGutterView(scrollView: scrollView, system: system)
        scrollView.verticalRulerView = gutterView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.gutterView = gutterView
        // The scroll view has not been laid out yet, so size the text view to
        // its content (with a minimum that matches the scroll view). The
        // vertically-resizable NSTextView will keep this in sync as the text
        // changes, and the initial content height guarantees the scroll knob
        // reflects the full document immediately.
        let width = max(scrollView.bounds.width, 100)
        // Estimate the content height for a correct scroll knob without
        // blocking on an O(n) layout pass. For documents under 100 KB we
        // compute the exact height; for larger documents we use a generous
        // sentinel and let the vertically-resizable NSTextView grow as-needed.
        let height: CGFloat
        if text.utf8.count < 100_000 {
            let font = system.textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            // Per-paragraph measurement: one `boundingRect` over a whole CJK/emoji document is quadratic.
            let contentHeight = system.contentHeightMeter.height(
                of: text as NSString,
                width: width,
                attributes: [.font: font]
            )
            height = max(contentHeight, scrollView.bounds.height)
        } else {
            height = max(50000, scrollView.bounds.height)
        }
        system.textView.frame = NSRect(
            origin: .zero,
            size: CGSize(width: width, height: height)
        )
        system.textView.autoresizingMask = [.width]
        system.applyPendingScrollOffset()

        system.textView.delegate = context.coordinator
        system.isDetachedFromEditorView = false
        context.coordinator.system = system
        context.coordinator.textBinding = $text
        context.coordinator.noteSynced(text)
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onScrollChange = onScrollChange
        context.coordinator.onLayoutChange = onLayoutChange
        scrollView.onWindowChange = { [weak coordinator = context.coordinator] in
            coordinator?.editorAttachmentDidChange()
        }

        registerCoordinatorObservers(scrollView: scrollView, coordinator: context.coordinator)

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let system = context.coordinator.system else { return }

        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onScrollChange = onScrollChange
        context.coordinator.onLayoutChange = onLayoutChange

        // Apply configuration changes (cheap because we diff at the call site
        // via SwiftUI's update cycle, but `apply` is idempotent).
        system.apply(configuration)

        // Only push model text into the view when it differs from the view's
        // current text *and* the change did not originate from the view itself.
        // This prevents the keystroke-echo feedback loop.
        var pushedModelText = false
        // While an IME / dead-key composition is in progress the binding still holds the pre-composition
        // text (marked-text updates post no `didChange`); pushing it would clear the marked range
        // mid-composition. The binding catches up when the composition commits.
        if !context.coordinator.isApplyingModelText, !system.textView.hasMarkedText(),
           !system.text.isExactlyEqual(to: text) {
            context.coordinator.isApplyingModelText = true
            system.setText(text)
            context.coordinator.isApplyingModelText = false
            context.coordinator.noteSynced(text)
            pushedModelText = true

            // A vertically-resizable NSTextView only grows its document-view
            // height when it is told to size to its content. Only call when
            // text was pushed from the model; user keystrokes already update
            // layout through the NSTextView directly.
            system.textView.sizeToFit()
        } else if !system.textView.hasMarkedText(), system.text.isExactlyEqual(to: text) {
            // Model and view agree (undo/redo, external replace and typing all end here): remember it, so a later
            // composition is not mistaken for a model replacement.
            context.coordinator.noteSynced(text)
        }

        // After any model push above (which bypasses the incremental
        // delegate hooks and rebuilds `lineIndex` wholesale in `setText`)
        // AND after a font-size preference change, either of which can
        // change the digit count/width the gutter needs -- calling this
        // BEFORE `setText` would read the pre-push `lineIndex`, leaving a
        // model replacement that crosses a digit boundary (e.g. 9 to 100
        // lines) stuck at the old ruler width until an unrelated later
        // update happened to trigger a redraw.
        context.coordinator.gutterView?.updateThickness()

        // Model pushes need a deferred measurement after TextKit has applied
        // the new text. Ordinary keystrokes already schedule a coalesced sync
        // from the text-view delegate; measuring here as well duplicated the
        // full-document layout pass on every binding update.
        if pushedModelText {
            system.scheduleFrameHeightSync()
        }

        scrollView.hasHorizontalScroller = !configuration.wrapsLines
        scrollView.autohidesScrollers = configuration.wrapsLines
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, NSTextViewDelegate {
        weak var system: EditorTextSystem?
        weak var gutterView: EditorGutterView?
        var textBinding: Binding<String>?
        var onSelectionChange: ((NSRange) -> Void)?
        var onScrollChange: ((Int) -> Void)?
        var onLayoutChange: (() -> Void)?
        var isApplyingModelText = false
        var sync = EditorModelSyncState()
        /// Captured in `shouldChangeTextIn` (every edit this delegate
        /// observes, any origin) and consumed in the very next
        /// `textDidChange` — see that method's doc comment for why this
        /// stays correct even across E10's nested edit interception and an
        /// `EditorEditTransaction`'s per-range multi-firing.
        private var pendingLineIndexEdit: (range: NSRange, replacementUTF16Length: Int)?

        /// Unconditionally keeps `system.lineIndex` current with EVERY edit
        /// this coordinator observes, independent of
        /// `isApplyingMultiRangeTransaction`'s SwiftUI-publication
        /// suppression below — an `EditorEditTransaction` with N ranges
        /// fires `textDidChange` N times (verified by
        /// `EditorEditTransactionTests.multiRangeIsOneUndoStepAndOnePublication`,
        /// the reason that suppression exists in the first place), and the
        /// line index must stay correct after every one of them, not just
        /// the transaction's final state.
        public func textDidChange(_: Notification) {
            // Marked-text edits post no didChange; whatever they changed must not survive into the cache.
            if let system, !system.isApplyingMultiRangeTransaction {
                system.storedSelectionSet = nil
            }
            system?.syncLineIndex(afterEdit: pendingLineIndexEdit)
            pendingLineIndexEdit = nil
            // The gutter has no way to know about a text edit on its own
            // (unlike scrolling, which NSRulerView already tracks via its
            // scroll view) — every edit needs an explicit redraw, and
            // `updateThickness()` also covers a line-count digit-width
            // change (e.g. line 9 -> 10, or 99 -> 100).
            if system?.isApplyingMultiRangeTransaction != true {
                gutterView?.updateThickness()
            }

            guard !isApplyingModelText,
                  let system,
                  !system.isPerformingProgrammaticTextUpdate,
                  !system.isApplyingMultiRangeTransaction
            else { return }
            if adoptReplacedModelIfNeeded(into: system) {
                return
            }
            isApplyingModelText = true
            textBinding?.wrappedValue = system.text
            isApplyingModelText = false
            noteSynced(system.text)
            system.noteTextEdit()
            // Typing changes the content height; keep the document view's
            // frame in step so the caret always has somewhere to scroll to.
            system.scheduleFrameHeightSync()
        }

        /// E10 typed-replacement hook. Returns `true` when AppKit should
        /// perform the original edit, `false` when the assist already applied
        /// a replacement (or moved the selection).
        public func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let system else { return true }
            guard let replacementString else { return true }
            // Captured before every branch below (including the E10/IME
            // early returns), since AppKit performs exactly
            // (affectedRange, replacementString) as the edit on every path
            // that returns `true` here, and a nested edit that vetoes this
            // one (E10 intercepting it) overwrites this same property with
            // ITS OWN (affectedRange, replacementString) before ITS OWN
            // `textDidChange` consumes it — see that method's doc comment.
            pendingLineIndexEdit = (affectedRange, (replacementString as NSString).length)
            if let oldSource = system.assistTextSource {
                system.preEditObserver?(affectedRange, replacementString, oldSource)
            }
            guard !isApplyingModelText else { return true }
            guard !system.isPerformingProgrammaticTextUpdate else { return true }
            guard !system.isPerformingEditingAssist else { return true }
            guard system.editingAssistConfiguration.isEnabled else { return true }

            // IME safety: marked text passes through untouched. A marked
            // range whose location is NSNotFound is never a real range.
            let marked = textView.markedRange()
            if textView.hasMarkedText() ||
                (marked.location != NSNotFound && NSIntersectionRange(marked, affectedRange).length > 0)
            // swiftlint:disable:next opening_brace
            {
                return true
            }

            // Fail open: without the expected live backing source, the editor
            // behaves exactly like native AppKit. Report the architecture
            // event in Debug rather than falling back to an O(document) copy.
            guard let source = system.assistTextSource else {
                assertionFailure("E10: live NSTextStorage backing source unavailable")
                return true
            }

            let outcome = MarkdownEditingAssistEngine.outcome(
                for: .replacement(range: affectedRange, string: replacementString),
                text: source,
                selection: system.selectedRange,
                configuration: system.editingAssistConfiguration,
                profile: system.languageEditingProfile
            )
            return !system.applyAssistOutcome(outcome)
        }

        /// E10 command hook. Returns `true` when the command was handled,
        /// `false` when AppKit should continue with the responder chain.
        public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let system else { return false }
            // Escape collapses a multi-selection to its primary range
            // regardless of the Markdown-assist configuration below (§6.9)
            // — multi-cursor collapse is not a Markdown editing assist. Still
            // gated on marked text, matching every other branch in this
            // method (line below): an active IME composition must let
            // native `cancelOperation:` cancel it, never get intercepted
            // here first.
            if selector == #selector(NSResponder.cancelOperation(_:)), !textView.hasMarkedText() {
                return collapseMultipleSelectionsIfNeeded(system: system)
            }
            // Multi-selection movement and delete run before the primary-only
            // Markdown command hook. Both are gated on IME, not on whether
            // Markdown assists are enabled; single-caret commands fall through.
            if !textView.hasMarkedText(), handleMultiSelectionKeyboardCommand(selector, system: system) {
                return true
            }
            if Self.isNewlineSelector(selector),
               handleLineEndingAwareNewline(textView, system: system, selector: selector) {
                return true
            }
            guard system.editingAssistConfiguration.isEnabled else { return false }
            guard !isApplyingModelText,
                  !system.isPerformingProgrammaticTextUpdate,
                  !system.isPerformingEditingAssist
            else { return false }
            if system.selectionSet.isMultiple, !textView.hasMarkedText(), textView.isEditable,
               let handled = handleMultiSelectionTab(selector, system: system) {
                return handled
            }
            // Marked text (IME composition) passes through untouched.
            guard !textView.hasMarkedText() else { return false }

            guard let action = Self.editingAssistAction(for: selector) else { return false }
            guard let source = system.assistTextSource else { return false }
            let outcome = MarkdownEditingAssistEngine.outcome(
                for: action,
                text: source,
                selection: system.selectedRange,
                configuration: system.editingAssistConfiguration,
                profile: system.languageEditingProfile
            )
            return system.applyAssistOutcome(outcome)
        }

        public func textViewDidChangeSelection(_: Notification) {
            guard let system else { return }
            system.cancelExternalViewportForChangedSelection()
            // Proactively invalidates a stale `selectionSet` cache for
            // every selection change EXCEPT the ones `selectionSet`'s own
            // setter itself just posted (`isUpdatingSelectionSet` guards
            // that) — see that property's doc comment (§6.10, Slice 3b-i)
            // for the exact coincidental-match bug this closes.
            if !system.isUpdatingSelectionSet {
                system.invalidateStoredSelectionSetIfStale()
            }
            system.invalidateCurrentLinePresentation()
            system.scheduleFrameHeightSync()
            // The semantic primary range, not AppKit's topmost one: with Cmd-D / Select All Matches the two differ, and
            // the status bar and both outlines follow this callback.
            onSelectionChange?(system.selectionSet.primaryRange)
        }

        /// Maps the AppKit text command selectors E10 understands. Everything
        /// else returns `nil` and falls through to native behavior.
        private static func editingAssistAction(for selector: Selector) -> EditingAssistAction? {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                .insertNewline
            case #selector(NSResponder.insertTab(_:)):
                .insertTab
            case #selector(NSResponder.insertBacktab(_:)):
                .insertBacktab
            case #selector(NSResponder.deleteBackward(_:)):
                .deleteBackward
            case #selector(NSResponder.moveToLeftEndOfLine(_:)):
                .smartHome
            default:
                nil
            }
        }

        // `scrollViewDidScroll(_:)`/`undoManagerDidChange(_:)` live in
        // `EditorView+Coordinator+Observers.swift` (extracted to keep this
        // file under its line-count limit).
    }
}
