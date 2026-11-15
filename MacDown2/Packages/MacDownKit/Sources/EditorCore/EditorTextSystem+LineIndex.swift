import AppKit

extension EditorTextSystem {
    /// Called once per atomic edit this text system observes — including
    /// once per individual range inside an `EditorEditTransaction`,
    /// independent of that transaction's own SwiftUI-publication
    /// suppression (`isApplyingMultiRangeTransaction`), since the line
    /// index must stay correct for every intermediate state, not just the
    /// transaction's final one.
    ///
    /// `editedRange` is in *pre-edit* coordinates. `newText` is read from
    /// `assistTextSource` — the live, backing `NSTextStorage.mutableString`
    /// (`EditorTextSystem+EditingAssists.swift`) — which by the time this
    /// is called already reflects the edit, with NO additional copy: it is
    /// the SAME buffer TextKit itself mutated, not a fresh materialization.
    /// This must never read from `text` (`textView.string`, bridged to a
    /// Swift `String`) instead: this codebase's own `assistTextSource`/
    /// `liveSourceLength` already document that `textView.string` is a
    /// real O(document length) materialization, treated elsewhere as "last
    /// resort only" — using it here on every keystroke would cost that
    /// copy on every keystroke and defeat the incremental index's entire
    /// purpose. `assistTextSource` can be `nil` only if the toolchain's
    /// TextKit 2 bridge is unavailable (see its own doc comment); falling
    /// back to `text as NSString` there is the same "fail open" trade the
    /// existing `liveSourceLength` makes.
    func noteIncrementalEdit(editedRange: NSRange, replacementUTF16Length: Int) {
        let live = assistTextSource ?? (text as NSString)
        // Marked-text (IME / dead-key) edits post no `didChange`, so the index never saw them; the
        // commit's edit would then be applied to a stale index and scan out of bounds. When the index's
        // length does not account for this edit exactly, rebuild instead of patching.
        guard lineIndex.utf16Length + replacementUTF16Length - editedRange.length == live.length else {
            rebuildLineIndex()
            return
        }
        lineIndex.applying(
            editedRange: editedRange,
            replacementUTF16Length: replacementUTF16Length,
            newText: assistTextSource ?? (text as NSString)
        )
        textChangeObserver?(.edit(range: editedRange, replacementLength: replacementUTF16Length))
    }

    /// Brings the line index in step after one change notification. Inside a multi-range transaction the
    /// per-range patches are skipped (each copies the whole line array) and the final notification rebuilds once.
    /// Observers (the Find model's retained search domain) still hear every range's `.edit`, highest first.
    func syncLineIndex(afterEdit pending: (range: NSRange, replacementUTF16Length: Int)?) {
        if isApplyingMultiRangeTransaction {
            lineIndexNeedsRebuild = true
            notifyEdit(pending)
        } else if lineIndexNeedsRebuild {
            lineIndexNeedsRebuild = false
            let live = assistTextSource ?? (text as NSString)
            if splicedEditPreservesLineBoundaries, let edits = transactionEditsToReport,
               lineIndex.utf16Length + edits.reduce(0, { sum, edit in
                   sum + (edit.replacementText as NSString).length - edit.range.length
               }) == live.length {
                lineIndex.applyLineNeutralEdits(edits)
            } else {
                lineIndex.rebuild(text: live)
            }
            if let edits = transactionEditsToReport {
                reportTransactionEdits(edits)
            } else {
                notifyEdit(pending)
            }
        } else if let pending {
            noteIncrementalEdit(editedRange: pending.range, replacementUTF16Length: pending.replacementUTF16Length)
        } else {
            // No edit was reported for this change (a composition's marked text): repair a stale index.
            rebuildLineIndexIfStale()
        }
    }

    private func notifyEdit(_ pending: (range: NSRange, replacementUTF16Length: Int)?) {
        guard let pending else { return }
        textChangeObserver?(.edit(range: pending.range, replacementLength: pending.replacementUTF16Length))
    }

    /// Repairs the line index when marked-text (IME / dead-key) edits, which post no `didChange`, left it out of step
    /// with the text — a cancelled composition over a selection changes the length with no edit ever reported.
    func rebuildLineIndexIfStale() {
        let live = assistTextSource ?? (text as NSString)
        if lineIndex.utf16Length != live.length {
            rebuildLineIndex()
        }
    }

    /// A composition ended (committed or cancelled). Rebuilds the index and, when the text no longer matches what
    /// was last published, tells the delegate so the binding catches up before the next SwiftUI update pass
    /// (which would otherwise push the stale binding back with `setText`, reverting the text and wiping undo).
    func compositionDidEnd() {
        rebuildLineIndex()
        storedSelectionSet = nil
        textView.didChangeText()
        compositionEndedObserver?()
    }

    /// Full rebuild for edit paths that bypass the incremental hook above
    /// entirely — currently just undo/redo (see `registerUndoRedoObservers()`
    /// below). Undo/redo are comparatively rare next to every-keystroke
    /// edits, so an O(n) rebuild here is an acceptable, simple trade
    /// against chasing a lower-level storage-delegate hook. Uses
    /// `assistTextSource` for the same no-extra-copy reason as
    /// `noteIncrementalEdit` above.
    func rebuildLineIndex() {
        lineIndex.rebuild(text: assistTextSource ?? (text as NSString))
        textChangeObserver?(.untracked)
    }

    /// Undo/redo replays a previously-approved edit directly against the
    /// text storage — it does NOT go through
    /// `NSTextViewDelegate.shouldChangeTextIn:replacementString:`/
    /// `textDidChange`, verified empirically
    /// (`EditorLineIndexWiringTests.undoAndRedoKeepLineIndexCorrect` failed
    /// without this: `text` correctly reverted via `NSTextView`'s own undo
    /// machinery, but `lineIndex` was never told about it at all).
    ///
    /// Registered on `EditorTextSystem` itself rather than on the SwiftUI
    /// `EditorView` layer, so this invariant holds for every consumer of
    /// this class — including tests that mount a bare `EditorTextSystem`
    /// without going through `EditorView.makeNSView` at all (an earlier
    /// version of this fix lived there, and a test using the lighter
    /// `EditingAssistIntegrationSupport.makeCoordinator` helper — which
    /// several other suites already relied on — proved it never ran).
    ///
    /// Deliberately does NOT capture `undoManager` once here and register
    /// against that fixed object: `undoManager` (`textView.undoManager ??
    /// fallbackUndoManager`) resolves to `fallbackUndoManager` at `init`
    /// time, since `NSTextView.undoManager` needs a real window to return
    /// its own — but once this text view IS installed in a window (as
    /// production always does, immediately after `init`), `textView.undoManager`
    /// switches to the WINDOW's own `NSUndoManager`, a different instance
    /// than whatever was captured earlier. An observer registered against
    /// the stale, no-longer-used `fallbackUndoManager` would never fire —
    /// exactly the failure this second version fixes, caught by the same
    /// test failing even after the observer moved to this class. Observing
    /// with `object: nil` (any sender) and re-resolving `self.undoManager`
    /// fresh inside the handler is correct regardless of when that identity
    /// changes, and the equality check discards notifications from any
    /// OTHER text system's undo manager (`NotificationCenter.default` is
    /// process-wide, not scoped to one instance).
    func registerUndoRedoObservers() {
        undoRedoObservers = [.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                // Extracted as `ObjectIdentifier` -- a plain, `Sendable`
                // value wrapping just the pointer identity -- rather than
                // keeping a reference to `notification.object` itself
                // (typed `Any?`) or to `notification` as a whole (neither
                // `Notification` nor Foundation's `UndoManager` is
                // `Sendable`). Swift's strict concurrency checking flags
                // passing either non-Sendable value into the
                // `assumeIsolated` closure below as a data-race risk, even
                // though this closure only ever runs on the main thread in
                // practice.
                let senderIdentity = (notification.object as AnyObject?).map(ObjectIdentifier.init)
                // `queue: nil` invokes this synchronously on the posting
                // thread, and AppKit's `UndoManager` always posts these on
                // the main thread — runtime-guaranteed but not statically
                // provable to the compiler, hence `assumeIsolated` rather
                // than a `Task { @MainActor in ... }` hop (which would
                // defer the rebuild to a later runloop turn instead of
                // keeping it synchronous with the undo/redo it reacts to).
                MainActor.assumeIsolated {
                    guard let self, senderIdentity == ObjectIdentifier(self.undoManager) else { return }
                    self.rebuildLineIndex()
                }
            }
        }
    }
}
