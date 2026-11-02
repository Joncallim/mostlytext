import AppKit
import Foundation

/// Owns exactly one document's live TextKit 2 text system.
///
/// This is a reference type isolated to `@MainActor` because every underlying
/// AppKit object is main-thread only. The store (``EditorTextSystemStore``)
/// caches one system per tab identity so undo history, selection, and scroll
/// position survive tab switches without recreating the text view.
@MainActor
public final class EditorTextSystem {
    /// The stable identity this system is cached under (typically a tab UUID).
    public let identity: String

    /// The text view presented to the user.
    public var textView: NSTextView {
        stack.textView
    }

    /// The content storage that holds the attributed string. E05's highlighter
    /// attaches here.
    public var contentStorage: NSTextContentStorage {
        stack.contentStorage
    }

    /// The layout manager that performs viewport-lazy layout. E05's highlighter
    /// may also attach here.
    public var layoutManager: NSTextLayoutManager {
        stack.layoutManager
    }

    /// Per-tab undo manager, independent of every other tab. `EditorTextView` hands
    /// this to AppKit (`NSTextView.undoManager` would otherwise be the WINDOW's), so
    /// Cmd-Z in one tab can never undo — or desynchronise the line index of —
    /// another tab that shares the window (tabbed documents).
    public let undoManager = UndoManager()

    private let stack: TextKitStack
    private var lastAppliedConfiguration: EditorConfiguration?
    private var lastAppliedOverscroll: OverscrollState?
    /// Not `private`: `EditorTextSystem+Content.swift`'s `setText`/
    /// `replaceTextFromExternal` also reset this on a whole-document
    /// replacement.
    var lastFrameSyncSignature: FrameSyncSignature?
    /// Not `private`: see `lastFrameSyncSignature`'s note above.
    var measuredContentHeight: CGFloat = 0
    var frameSyncTask: Task<Void, Never>?
    /// Not `private`: `EditorTextSystem+Content.swift`'s `setText`/
    /// `replaceTextFromExternal` bump this on every whole-document
    /// replacement, mirroring the incremental-edit path's own bump in
    /// `noteTextEdit()` below.
    var editRevision: UInt64 = 0
    var lastExternalReplacementText: String?
    /// `true` while no `EditorView` hosts this system (Preview Only, between mounts): its text view has no delegate,
    /// so an edit made now would never reach the model and would be reverted by the next mount.
    public internal(set) var isDetachedFromEditorView = false

    /// Told about every text change (see `EditorTextChange`); nil when nobody is watching.
    public var textChangeObserver: ((EditorTextChange) -> Void)?
    let metricsCache = EditorDocumentMetricsCache()
    let contentHeightMeter = ContentHeightMeter()
    /// Prevents a disk-driven replacement from flowing back through the
    /// editor binding as a user edit. Setter is `internal` (not `private`)
    /// so `EditorTextSystem+Content.swift`'s `replaceTextFromExternal` can
    /// raise/lower it.
    public internal(set) var isPerformingProgrammaticTextUpdate = false
    /// Set while an E10 assist edit is being applied, so the nested
    /// `shouldChangeTextIn` callback does not re-transform the assist.
    /// The setter is internal so the adapter in
    /// `EditorTextSystem+EditingAssists.swift` can raise it around the edit.
    public internal(set) var isPerformingEditingAssist = false
    /// Set while an `EditorEditTransaction` with more than one replacement
    /// is applying all but its last `insertText` call, so
    /// `EditorView.Coordinator.textDidChange` suppresses the intermediate
    /// AppKit change notifications those calls individually post and
    /// publishes exactly once, after the whole transaction has landed —
    /// "one command, one publication" for N &gt; 1 ranges, matching the
    /// existing single-range patterns' one-publication guarantee. The
    /// setter is internal so `EditorEditTransaction.swift`'s `apply(_:)`
    /// can raise/lower it around the loop.
    public internal(set) var isApplyingMultiRangeTransaction = false
    /// Set when a multi-range transaction skipped its per-range line-index patches; the transaction's final
    /// change notification then rebuilds the index once instead of patching it N times (each patch copies the
    /// whole line array, which made Replace All quadratic).
    var lineIndexNeedsRebuild = false
    /// The original replacements of a spliced transaction, reported to observers instead of the one wide edit.
    var transactionEditsToReport: [TextReplacement]?
    /// The assist configuration currently applied to this text system.
    /// Storage lives here (extensions cannot hold stored properties);
    /// the E10 methods live in `EditorTextSystem+EditingAssists.swift`.
    public private(set) var editingAssistConfiguration: EditingAssistConfiguration = .disabled
    /// The active document format's editor mechanics (EPIC-22 §6.11,
    /// Slice 4a) — set alongside `editingAssistConfiguration`, from the same
    /// `EditorConfiguration.apply(_:)` call.
    public private(set) var languageEditingProfile: LanguageEditingProfile = .plainText
    /// Set by `scrollOffset`'s setter before the scroll view exists yet
    /// (session restore); applied by `applyPendingScrollOffset()` once it does.
    var pendingScrollOffset: CGFloat?
    var pendingExternalViewport: EditorViewportSnapshot?
    var pendingExternalViewportRevision: UInt64?
    /// Kept current with every edit this text system observes, incrementally
    /// (never a full rescan except on whole-document replacement). Powers
    /// the gutter, status bar, and Go to Line/Column. Setter is `internal`
    /// (not `private`) so `EditorTextSystem+LineIndex.swift` can maintain
    /// it — see that file for the update/rebuild methods and the
    /// undo/redo observer that keeps it correct across those, which bypass
    /// the normal incremental-edit path entirely.
    public internal(set) var lineIndex: EditorLineIndex
    /// See `EditorTextSystem+LineIndex.swift`'s `registerUndoRedoObservers()`.
    var undoRedoObservers: [NSObjectProtocol] = []
    /// Backing storage for `selectionSet` (`EditorTextSystem+Selection.swift`)
    /// — see that property's doc comment for why a plain computed
    /// reconstruction from `textView.selectedRanges` cannot, on its own,
    /// preserve a non-zero `primaryIndex` across a read-after-write.
    var storedSelectionSet: EditorSelectionSet?
    /// Set while `selectionSet`'s own setter is writing to
    /// `textView.selectedRanges` (including its own AppKit-collapse-revert
    /// branch), so `EditorView.Coordinator.textViewDidChangeSelection`'s
    /// staleness check on that same notification does not immediately
    /// invalidate the cache the setter just wrote. See
    /// `EditorTextSystem+Selection.swift` for the full mechanism this
    /// guards.
    var isUpdatingSelectionSet = false

    /// Snapshot of the inputs that produced the current overscroll inset so we
    /// can skip redundant updates.
    private struct OverscrollState: Equatable {
        let enabled: Bool
        let height: CGFloat
        let textInsets: NSSize
    }

    /// Snapshot of the inputs that produced the last frame-height sync, so
    /// `syncFrameHeightToContent()` can skip the (TextKit 2 layout) work when
    /// neither has changed. Not `private`: `lastFrameSyncSignature`'s own
    /// type must be at least as visible as that property.
    struct FrameSyncSignature: Equatable {
        let textLength: Int
        let width: CGFloat
        let editRevision: UInt64
    }

    /// The scroll view that owns the text view. Weak because the scroll view
    /// (via its document view) already strongly references the text view, and
    /// the store strongly references this system.
    weak var scrollView: NSScrollView?

    /// Creates a text system for `identity` with the given initial text and
    /// configuration. The caller should cache the result and reuse it across
    /// view lifecycles.
    public init(identity: String, initialText: String, configuration: EditorConfiguration) {
        self.identity = identity
        stack = TextKitStack()
        // `setText` below performs the single authoritative
        // `lineIndex.rebuild` scan of `initialText`; starting from an empty
        // index here avoids scanning the same text twice on every open.
        lineIndex = EditorLineIndex(text: "" as NSString)
        // `self` is fully initialized as of this point (every stored
        // property without a default has now been assigned), so it is safe
        // to hand a reference to the text view here — see
        // `EditorTextView.owningSystem`'s doc comment for why it needs one.
        (stack.textView as? EditorTextView)?.owningSystem = self
        apply(configuration)
        setText(initialText)
        registerUndoRedoObservers()
    }

    // MARK: - Content

    // `setText`/`viewportSnapshot`/`replaceTextFromExternal` live in
    // `EditorTextSystem+Content.swift` (extracted to keep this file under
    // its line-count limit, mirroring the established
    // `DocumentEditorSplitView+EditorPane.swift` precedent).

    /// The current plain-text content of the editor.
    public var text: String {
        textView.string
    }

    /// Monotonic content generation used by caches whose inputs can change
    /// without changing the UTF-16 length (for example, newline edits).
    public var contentRevision: UInt64 {
        editRevision
    }

    func noteTextEdit() {
        editRevision &+= 1
    }

    // MARK: - Configuration

    /// Applies editor preferences to the underlying text view and text container.
    public func apply(_ configuration: EditorConfiguration) {
        let configurationChanged = configuration != lastAppliedConfiguration
        if configurationChanged {
            lastAppliedConfiguration = configuration
            // Font, insets, line height and wrap mode all change the layout height without touching the text, width
            // or edit revision the frame-sync signature is made of: invalidate it so the next sync re-measures
            // instead of reinstalling the old measured height (too short after a larger font, too long after a
            // smaller).
            lastFrameSyncSignature = nil
            editingAssistConfiguration = configuration.editingAssists
            languageEditingProfile = configuration.languageProfile

            textView.font = configuration.font
            textView.textContainerInset = configuration.textInsets
            (textView as? EditorTextView)?.showsInvisibles = configuration.showsInvisibles

            // Plain-text editing: Markdown source must not be silently mutated by
            // smart substitutions or rich-text parsing. These are applied here so
            // they stay reactive if a future preference toggle changes them.
            textView.isRichText = false
            textView.smartInsertDeleteEnabled = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false

            // Word wrap: when wrapping, the container tracks the clip view width.
            // When not wrapping, the container is given a very large width and the
            // text view is allowed to resize horizontally.
            stack.textContainer.widthTracksTextView = configuration.wrapsLines
            stack.textContainer.heightTracksTextView = false
            if configuration.wrapsLines {
                stack.textContainer.containerSize = NSSize(
                    width: textView.frame.width,
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.isHorizontallyResizable = false
                textView.autoresizingMask = [.width]
            } else {
                stack.textContainer.containerSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.isHorizontallyResizable = true
                textView.autoresizingMask = [.height]
            }

            // Line height applied as the base typing attribute. This is a base
            // layer; E05's highlighter can layer additional attributes on top.
            let paragraphStyle = NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle
            paragraphStyle?.lineHeightMultiple = configuration.lineHeightMultiple
            if let paragraphStyle {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: configuration.font,
                    .paragraphStyle: paragraphStyle,
                ]
                textView.typingAttributes = attributes
            }
        }

        // Always apply overscroll, even when the configuration hasn't changed.
        // The correct padding depends on the scroll view's frame, which is not
        // known when the text system is first created (either here or in
        // `EditorView.makeNSView`). Re-applying is cheap because it de-duplicates
        // by the current frame height and enabled flag.
        applyOverscroll(configuration.scrollsPastEnd)
    }

    private func applyOverscroll(_ enabled: Bool) {
        guard let scrollView else { return }
        let height = scrollView.frame.height
        let textInsets = lastAppliedConfiguration?.textInsets ?? .zero
        let current = OverscrollState(enabled: enabled, height: height, textInsets: textInsets)
        if let lastAppliedOverscroll, lastAppliedOverscroll == current {
            return
        }
        lastAppliedOverscroll = current

        let overscrollHeight: CGFloat = enabled ? height : 0
        // Add a bottom content inset so the last line can scroll to the top.
        textView.textContainerInset = NSSize(
            width: textInsets.width,
            height: textInsets.height + overscrollHeight
        )
    }

    /// Corrects the text view's frame height against TextKit 2's real,
    /// laid-out content bounds.
    ///
    /// `isVerticallyResizable = true` does not, on its own, keep this
    /// manually-constructed TextKit 2 stack's frame in sync with content
    /// outside the viewport-lazy layout pass — nothing here ever asks the
    /// layout manager to lay out beyond what has actually been visible, so
    /// the frame stays close to whatever `EditorView.makeNSView`'s initial
    /// (plain `NSString.boundingRect`, and at that point almost certainly the
    /// wrong width — the scroll view has not been laid out yet) estimate
    /// produced. Scrolling — via `scrollRangeToVisible`, keyboard caret
    /// navigation, or manual scroll — has nowhere further to go once the
    /// frame stops growing, which reads as "scrolling doesn't work" even
    /// though the selection/caret genuinely moved.
    ///
    /// Uses Foundation text measurement instead of forcing TextKit 2 to
    /// materialize every off-screen fragment. This keeps the editing path
    /// responsive while still tracking wrapping changes.
    ///
    /// The computed height is re-measured fresh for each distinct (text
    /// length, width) signature — it is NOT accumulated as a running maximum
    /// across signatures. A previous, different width or text length can
    /// genuinely need a *different* height (a narrower container wraps to
    /// more lines; shorter text needs less), so an earlier signature's
    /// height is not a valid floor for a new one. Carrying it forward as one
    /// left the frame stuck too tall after a pane resize or a large
    /// deletion — a permanent blank gap below the actual content.
    func syncFrameHeightToContent() {
        guard let scrollView else { return }
        let string = textView.string as NSString

        // Matching text/width does NOT mean the frame still matches the last
        // measurement: TextKit 2's viewport controller reclaims off-screen
        // fragments on its own schedule and has been observed shrinking
        // `textView.frame` between calls with nothing here to invalidate the
        // signature. Skipping the reapplication below left it stuck shrunk,
        // so a later `scrollRangeToVisible` (e.g. the outline's
        // jump-to-heading) clamped against it and landed far from the target.
        let signature = FrameSyncSignature(
            textLength: string.length,
            width: textView.frame.width,
            editRevision: editRevision
        )
        guard signature != lastFrameSyncSignature else {
            applyMeasuredFrameHeight(scrollView: scrollView)
            return
        }
        lastFrameSyncSignature = signature

        let availableWidth = max(textView.frame.width - textView.textContainerInset.width * 2, 1)
        let contentHeight = contentHeightMeter.height(
            of: string,
            width: availableWidth,
            attributes: textView.typingAttributes
        )
        measuredContentHeight = contentHeight + textView.textContainerInset.height * 2
        applyMeasuredFrameHeight(scrollView: scrollView)
    }

    /// Syncs `textView.frame.height` to exactly what `measuredContentHeight`
    /// (for the current signature) requires — growing OR shrinking it, since
    /// both a stale-small frame (TextKit 2 shrank it behind our back) and a
    /// stale-large one (carried over from a since-resized/edited signature)
    /// are equally wrong.
    private func applyMeasuredFrameHeight(scrollView: NSScrollView) {
        let neededHeight = max(measuredContentHeight, scrollView.bounds.height)
        if textView.frame.height != neededHeight {
            textView.frame.size.height = neededHeight
        }
    }

    // MARK: - Teardown

    /// Breaks internal references so the text system can deallocate.
    ///
    /// Call this before evicting the system from the cache. It severs the
    /// text-view delegate and breaks the layout graph held by the stack.
    func prepareForDeallocation() {
        frameSyncTask?.cancel()
        frameSyncTask = nil
        textView.delegate = nil
        stack.layoutManager.textContainer = nil
        undoRedoObservers.forEach(NotificationCenter.default.removeObserver)
        undoRedoObservers = []
    }
}
