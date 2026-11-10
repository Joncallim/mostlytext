import AppKit

/// `NSTextView` subclass that draws TextKit-2-safe invisible characters
/// (spaces, tabs, line endings) directly within the text content area
/// (epic-22-implementation.md §6.8, §17 Slice 2c).
///
/// This is a `draw(_:)` override rather than a separate overlay `NSView`:
/// AppKit already calls `draw(_:)` with a viewport-clamped dirty rect on
/// exactly the right schedule (scroll, edit, initial display), so a second
/// view would need to reinvent that scroll/invalidation synchronization for
/// no benefit. Never touches `layoutManager` (the legacy TextKit 1
/// accessor) — only `textLayoutManager`, the TextKit 2 API.
@MainActor
public final class EditorTextView: NSTextView {
    /// Set once by `EditorTextSystem.init`, after `self` is fully
    /// initialized, so this view can route multi-selection typing/delete
    /// through `EditorTextSystem`'s `EditorEditTransaction` chokepoint
    /// (§6.9, §7.2, Slice 3a). Weak: the text system owns this view (via
    /// `TextKitStack`), never the reverse.
    weak var owningSystem: EditorTextSystem?

    /// The owning tab's own undo manager rather than the window's shared one.
    override public var undoManager: UndoManager? {
        owningSystem?.undoManager ?? super.undoManager
    }

    /// Edit ▸ Undo / Redo. `NSWindow` is the only stock responder that implements `undo:`/`redo:`,
    /// and it acts on the WINDOW's undo manager — an empty one now that every tab owns its own — so
    /// the text view answers them itself, ahead of the window in the responder chain.
    @objc public func undo(_: Any?) {
        cancelComposition()
        undoManager?.undo()
    }

    @objc public func redo(_: Any?) {
        cancelComposition()
        undoManager?.redo()
    }

    override public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)):
            (item as? NSMenuItem)?.title = undoManager?.undoMenuItemTitle ?? String(localized: "Undo", bundle: .module)
            return undoManager?.canUndo ?? false
        case #selector(redo(_:)):
            (item as? NSMenuItem)?.title = undoManager?.redoMenuItemTitle ?? String(localized: "Redo", bundle: .module)
            return undoManager?.canRedo ?? false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    /// Non-nil for exactly the duration of a gesture that STARTED as a
    /// plain Option-click (§6.10, Slice 3b-iv): the view-space point
    /// `mouseDown(with:)` captured. `mouseDragged(with:)` uses it as the
    /// drag's fixed anchor corner on every subsequent event; `nil` means
    /// the current gesture (if any) is an ordinary, non-Option one and
    /// every override below falls through to `super` unchanged. Being
    /// non-nil does NOT by itself mean rectangular selection has engaged —
    /// see `didDragRectangularSelection` below.
    private var optionDragAnchorViewPoint: CGPoint?

    /// `true` once the current Option gesture has moved far enough from
    /// `optionDragAnchorViewPoint` to count as a genuine drag rather than a
    /// stationary click (`Self.dragActivationThreshold`). Distinguishing
    /// this from "an anchor is set" matters: without it, `mouseUp(with:)`
    /// would recompute a degenerate, single-point "rectangle" for EVERY
    /// plain Option-click (since a real click's own mouseUp always fires,
    /// even with zero mouse movement) and silently overwrite
    /// `mouseDown(with:)`'s own toggle-caret result the instant the button
    /// is released — turning a working single-click toggle into a no-op.
    private var didDragRectangularSelection = false

    /// Minimum view-space distance from the anchor before an Option-drag
    /// counts as a genuine rectangular-selection gesture rather than
    /// ordinary hand tremor during a click — real pointing hardware rarely
    /// reports two events at the exact same point even for a gesture a
    /// user experiences as "just a click."
    private static let dragActivationThreshold: CGFloat = 4

    /// Public: `EditorTextSystem.apply(_:)` sets this from
    /// `EditorConfiguration.showsInvisibles`.
    public var showsInvisibles = false {
        didSet {
            guard showsInvisibles != oldValue else { return }
            needsDisplay = true
        }
    }

    /// Public: the `Highlighting` module's `NeonSyntaxHighlighter.applyChrome(theme:)`
    /// sets this from `Theme.chrome.invisibles`.
    public var invisiblesColor: NSColor = .tertiaryLabelColor {
        didSet {
            guard showsInvisibles else { return }
            needsDisplay = true
        }
    }

    /// Theme-owned editor decoration. Unbound editors keep their existing
    /// system presentation; the highlighter forwards the shared resolved roles.
    public var currentLineColor: NSColor = .clear {
        didSet {
            guard currentLineColor != oldValue else { return }
            owningSystem?.invalidateCurrentLinePresentation()
        }
    }

    public var gutterForegroundColor: NSColor? {
        didSet { enclosingScrollView?.verticalRulerView?.needsDisplay = true }
    }

    public var gutterBackgroundColor: NSColor? {
        didSet { enclosingScrollView?.verticalRulerView?.needsDisplay = true }
    }

    override public func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLineBackground(in: rect)
    }

    /// Current-document Find match ranges to highlight (EPIC-22 §6.14, Slice
    /// 5a), set via `EditorTextSystem.setFindHighlights(ranges:currentIndex:)`.
    /// Empty when the Find bar is closed or has no query. Not `private`:
    /// read by `EditorTextViewFindHighlightTests` to verify forwarding
    /// without needing to assert on actual pixel output.
    private(set) var findHighlightRanges: [NSRange] = []
    private(set) var currentFindMatchIndex: Int?

    /// Updates the highlighted match ranges/current index, redrawing only
    /// when something actually changed — this is called on every keystroke
    /// typed into the Find bar's query field via
    /// `EditorFindModel.updateMatches(in:)`.
    func setFindHighlights(ranges: [NSRange], currentIndex: Int?) {
        guard ranges != findHighlightRanges || currentIndex != currentFindMatchIndex else { return }
        findHighlightRanges = ranges
        currentFindMatchIndex = currentIndex
        needsDisplay = true
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Find highlights are translucent and drawn AFTER the view's own drawing: drawn
        // before `super.draw(_:)` — as they once were — the background fill painted over
        // them, so no match was ever visible.
        if !findHighlightRanges.isEmpty, let textLayoutManager {
            drawFindHighlights(in: dirtyRect, layoutManager: textLayoutManager)
        }
        if showsInvisibles, let textLayoutManager {
            drawInvisibles(in: dirtyRect, layoutManager: textLayoutManager)
        }
        drawSecondaryCarets()
    }

    /// Multi-selection typing (§6.9, §7.2): when more than one selection is
    /// active, `owningSystem.applyMultiCursorInsert(_:)` replaces every one
    /// of them with the typed text and returns `true`; `super` is not
    /// called in that case, since calling it too would insert the text a
    /// second time at whichever range AppKit itself considers primary.
    /// `replacementRange.location != NSNotFound` means this call already
    /// targets one specific, explicit range — including each of the N
    /// individual sub-edits `EditorEditTransaction.apply(_:)` itself makes
    /// through this same override while fanning out — so those always fall
    /// through to `super` unchanged, exactly as before this override
    /// existed. Synthetic bare carets live in the owning system's
    /// `selectionSet` cache when AppKit cannot retain them in
    /// `selectedRanges`; the same transaction inserts at those carets.
    override public func insertText(_ string: Any, replacementRange: NSRange) {
        if replacementRange.location == NSNotFound,
           let owningSystem, let text = string as? String,
           owningSystem.applyMultiCursorInsert(text) {
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Multi-selection delete (§6.9, §7.2): `deleteBackward`/`deleteForward`
    /// share one selection-deleting implementation, since every range in a
    /// real multi-selection is non-empty (see
    /// `applyMultiCursorDeleteSelection()`'s doc comment) and deleting a
    /// selection's own content is direction-independent.
    override public func deleteBackward(_ sender: Any?) {
        if let owningSystem, owningSystem.applyMultiCursorDeleteSelection() {
            return
        }
        super.deleteBackward(sender)
    }

    override public func deleteForward(_ sender: Any?) {
        if let owningSystem, owningSystem.applyMultiCursorDeleteSelection() {
            return
        }
        super.deleteForward(sender)
    }

    /// Multi-selection paste (§6.9, §7.2) needs its own override, separate
    /// from `insertText`: found empirically (a real, pasteboard-backed test)
    /// that `NSTextView.paste(_:)` performs the operation as two SEPARATE
    /// `insertText` calls — an empty-string "delete the current selection(s)"
    /// call, then a text "insert" call — rather than one. Once the first
    /// call's multi-range delete correctly empties every selection, AppKit's
    /// own selection collapses to a single caret (the same collapse this
    /// file's `insertText`/`deleteBackward` docs already describe for
    /// multiple simultaneous zero-length ranges), so the second call would
    /// only ever insert the pasted text at ONE location — silently losing
    /// the other selections' paste. Reading the pasteboard directly and
    /// routing it through `applyMultiCursorInsert(_:)` in one step, before
    /// AppKit's own two-step sequence begins, avoids that entirely. Plain
    /// string only, matching this editor's plain-text-only design
    /// (`EditorTextSystem.apply(_:)` already sets `isRichText = false`).
    override public func paste(_ sender: Any?) {
        if let owningSystem, let text = NSPasteboard.general.string(forType: .string),
           owningSystem.applyMultiCursorInsert(text) {
            return
        }
        super.paste(sender)
    }

    /// Option-click add/remove caret (§6.10, Slice 3b-ii). A plain
    /// (single-click) Option-click resolves the click point to a character
    /// offset and toggles a secondary caret there via
    /// `EditorTextSystem.toggleSecondaryCaret(at:)`; anything else (no
    /// Option, or more than one click) falls through to `super.mouseDown(_:)`
    /// unchanged. Not calling `super` for a handled Option-click also means
    /// AppKit's own internal drag-tracking loop never starts for it, so an
    /// Option-*drag* does nothing beyond placing the initial caret — the
    /// correct minimal scope here; rectangular/column selection via
    /// Option-drag is Slice 3b-iv's own, separate feature.
    ///
    /// Point-to-offset resolution uses `NSTextInputClient.characterIndex(for:)`
    /// (screen-space), confirmed empirically against this exact TextKit 2
    /// stack (round-tripped through `firstRect(forCharacterRange:)`'s
    /// already-verified offset-to-point mapping, exact for 7 offsets
    /// spanning a line wrap) — a different, more precise tool than
    /// `EditorTextSystem+Scroll.swift`'s `topVisibleUTF16Offset`, which only
    /// ever needed fragment-level granularity, not an exact character
    /// position within a line.
    override public func keyDown(with event: NSEvent) {
        owningSystem?.cancelPendingExternalViewport()
        super.keyDown(with: event)
    }

    override public func mouseDown(with event: NSEvent) {
        owningSystem?.cancelPendingExternalViewport()
        // Reset defensively at the top of every mouseDown, regardless of
        // branch, so a gesture that ends without ever reaching
        // `mouseUp(with:)` (never actually observed, but not provable
        // impossible either) can't leak stale drag state into the next,
        // unrelated gesture.
        optionDragAnchorViewPoint = nil
        didDragRectangularSelection = false
        if Self.isPlainOptionClick(event), let owningSystem, let window {
            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            let handled = owningSystem.toggleSecondaryCaret(at: characterIndex(for: screenPoint))
            // Arm rectangular-drag tracking regardless of `handled`: a
            // rectangular drag is a distinct gesture from the plain-click
            // toggle above (§6.10, Slice 3b-iv). If the user drags far
            // enough from here, `mouseDragged(with:)` REPLACES
            // `selectionSet` wholesale with the rectangle — it does not
            // depend on, or need to undo, whatever the toggle above just
            // did. If no drag ever follows, the toggle's own result
            // (including a declined `false`, e.g. an offset strictly
            // inside a real selection) stands unchanged: see
            // `didDragRectangularSelection`'s own doc comment for why that
            // distinction is load-bearing, not cosmetic.
            optionDragAnchorViewPoint = convert(event.locationInWindow, from: nil)
            if handled {
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Rectangular (column) selection via Option-drag (§6.10, Slice 3b-iv).
    /// Only engages once the gesture has moved past
    /// `Self.dragActivationThreshold` from an Option-click's own anchor;
    /// below that, or for any gesture that didn't start as a plain
    /// Option-click at all (including one where `toggleSecondaryCaret`
    /// itself declined), this is a no-op — sub-threshold movement is
    /// deliberately swallowed rather than falling through to
    /// `super.mouseDragged(with:)`, since starting native drag-selection
    /// mid-gesture on what is still, as far as the user is concerned, a
    /// stationary Option-click would be a visible glitch of its own.
    /// Recomputes the full rectangular selection fresh from the fixed
    /// anchor and the current point on every call, rather than
    /// incrementally adjusting the previous one: matches every other
    /// selection recomputation in this codebase
    /// (`EditorTextSystem+SynchronizedMovement.swift`'s own per-caret
    /// recomputation, for one) and is simple enough at realistic document
    /// sizes that no incremental-update optimization is justified without
    /// a measured need for one.
    override public func mouseDragged(with event: NSEvent) {
        guard let anchor = optionDragAnchorViewPoint, let owningSystem else {
            super.mouseDragged(with: event)
            return
        }
        let currentPoint = convert(event.locationInWindow, from: nil)
        guard didDragRectangularSelection || hypot(currentPoint.x - anchor.x, currentPoint.y - anchor.y) >= Self
            .dragActivationThreshold
        else {
            return
        }
        didDragRectangularSelection = true
        owningSystem.applyRectangularSelection(fromViewPoint: anchor, toViewPoint: currentPoint)
    }

    /// Finishes an Option gesture. If it never crossed the drag-activation
    /// threshold, this is a no-op beyond clearing state: `mouseDown(with:)`'s
    /// own toggle-caret result (or lack thereof) stands as final, exactly
    /// matching this method's behavior before this slice, when no override
    /// existed here at all. If it DID become a genuine rectangular drag,
    /// performs one final update at the exact release point — the last
    /// `mouseDragged(with:)` event may have landed a pixel or two short of
    /// it. `super.mouseUp(with:)` is always called afterward: since
    /// `mouseDown(with:)` never calls `super` for a handled Option-click,
    /// there is no native tracking-loop state for `super.mouseUp(with:)` to
    /// interact with here — calling it is a harmless, defensive default
    /// rather than a behavioral requirement.
    override public func mouseUp(with event: NSEvent) {
        finishRectangularSelectionGesture(atViewPoint: convert(event.locationInWindow, from: nil))
        super.mouseUp(with: event)
    }

    /// `mouseUp(with:)`'s own logic, extracted into a plain method that
    /// never itself touches `super` — deliberately, so
    /// `EditorRectangularSelectionTests` can call it directly instead of
    /// driving the real `mouseUp(with:)` override. Found empirically (a
    /// real, synthetic-event test that hung past the test runner's own
    /// timeout during this slice's development, the same class of failure
    /// `isPlainOptionClick(_:)`'s own doc comment already documents for
    /// `mouseDown`): `NSTextView.mouseUp(with:)`'s real implementation, like
    /// `mouseDown(with:)`, has internal behavior that expects a live
    /// `NSApplication` event queue behind it and hangs indefinitely against
    /// one isolated synthetic event with no real queue supplying whatever
    /// it is waiting for. This is not a risk in real, running-app usage
    /// (`super.mouseUp(with:)` already ran, safely, after every Option-click
    /// even before this slice added an explicit override here, since with
    /// no override at all the inherited default simply ran unfiltered) —
    /// only an isolated, single-event test call is at risk.
    func finishRectangularSelectionGesture(atViewPoint currentPoint: CGPoint) {
        if didDragRectangularSelection, let anchor = optionDragAnchorViewPoint, let owningSystem {
            owningSystem.applyRectangularSelection(fromViewPoint: anchor, toViewPoint: currentPoint)
        }
        optionDragAnchorViewPoint = nil
        didDragRectangularSelection = false
    }

    /// `true` for exactly the click `mouseDown(with:)` intercepts: Option
    /// held, single click. Extracted as a pure, testable predicate — an
    /// independent hostile review noted that driving a REAL `mouseDown(with:)`
    /// call in a test to check this condition risks the modal-tracking-loop
    /// hang documented above, so this lets `EditorOptionClickTests` cover
    /// the guard itself directly without that risk.
    static func isPlainOptionClick(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.option) && event.clickCount == 1
    }

    // `drawSecondaryCarets` lives in `EditorTextView+SecondaryCarets.swift`
    // (extracted to stay under this file's line-count budget, mirroring
    // `drawFindHighlights`'s own extraction into
    // `EditorTextView+FindHighlights.swift`).
}
