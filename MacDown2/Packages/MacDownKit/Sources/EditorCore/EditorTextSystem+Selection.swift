import AppKit

// MARK: - Multi-range selection (EPIC-22 §6.9, §6.10, §7.1, Slices 3a/3b-i)

public extension EditorTextSystem {
    /// The current selection, as the plural sibling of `selectedRange`
    /// (`EditorTextSystem+Scroll.swift`), which remains unchanged and keeps
    /// returning `textView.selectedRange()` — confirmed empirically (against
    /// a real mounted text view, in `EditorMultiSelectionTests`) that
    /// AppKit's own single-range accessor always agrees with the first
    /// (topmost) entry of `selectedRanges`, the same range this type's own
    /// from-AppKit reconstruction below treats as primary by default.
    ///
    /// AppKit's `selectedRanges` has no concept of "primary" at all, and
    /// (§6.9's architecture-correction note) cannot even hold more than one
    /// simultaneous zero-length (bare-caret) range, or a mix of one with
    /// anything else, at any spacing — confirmed empirically with direct
    /// probes. So this property's `storedSelectionSet` cache is the actual
    /// source of truth for a caret set AppKit itself cannot fully
    /// corroborate.
    ///
    /// Keeping that cache correct requires actively invalidating it whenever
    /// selection changes through any path other than this property's own
    /// setter — an independent hostile review of PR #129 found, by hand-
    /// tracing a real sequence, that relying ONLY on a reactive "does the
    /// cache still match AppKit" check in this getter is not enough: after
    /// the setter's own AppKit-collapse-revert leaves `textView.selectedRanges`
    /// showing just the primary, ANY later, unrelated event that happens to
    /// return the live selection to that exact same primary offset (the
    /// user clicking away and back, an outline jump-back, an unrelated
    /// `EditorTextSystem+Scroll.swift` `selectedRange`/`revealSelection`
    /// call, undo) would satisfy this getter's own `liveRanges ==
    /// [cached.primaryRange]` check and wrongly resurrect a stale secondary
    /// caret that has nothing to do with the user's current intent — and,
    /// via `EditorTextSystem+MultiCursor.swift`'s `applyMultiCursorInsert`,
    /// could fan an ordinary keystroke out to that phantom location too.
    ///
    /// The actual fix is proactive, not reactive:
    /// `EditorView.Coordinator.textViewDidChangeSelection` calls
    /// `invalidateStoredSelectionSetIfStale()` on every selection-changed
    /// notification EXCEPT while `isUpdatingSelectionSet` is true (i.e.
    /// except for the notifications this property's own setter posts while
    /// writing), so any selection change through any other path clears a
    /// now-stale cache before a later coincidental match could ever
    /// resurrect it. `setText`/`replaceTextFromExternal` (whole-document
    /// replacement) also explicitly clear it, for the same reason
    /// (offsets from a previous document are never valid for a new one,
    /// even if a coincidental primary match would otherwise pass).
    ///
    /// This getter's own two-condition check on `storedSelectionSet` below
    /// remains as defense in depth — by the time the proactive invalidation
    /// above is in place, the cache should already be `nil` whenever it
    /// would otherwise be stale, but the check costs nothing extra and
    /// guards against a gap in that proactive coverage the getter's own
    /// logic doesn't yet know about:
    /// 1. `cached.ranges == liveRanges` — the write fully survived AppKit's
    ///    own representation (a genuine, non-touching multi-*selection*,
    ///    e.g. what Select-All-Occurrence/Slice 3c produces), so the cache
    ///    is exactly what AppKit itself also reports, including a non-zero
    ///    `primaryIndex`.
    /// 2. `liveRanges == [cached.primaryRange]` — the setter's own write
    ///    could not fully survive (a bare caret beyond the first, or a
    ///    touching pair, silently collapsed/merged by AppKit) and
    ///    correctly reverted AppKit's visible state to just the primary
    ///    range; the cache is still the correct, full-fidelity model,
    ///    AppKit just cannot display all of it natively —
    ///    `EditorTextView`'s own secondary-caret drawing pass (§6.10,
    ///    Slice 3b-i) is what makes the rest visible.
    var selectionSet: EditorSelectionSet {
        get {
            let liveRanges = textView.selectedRanges.map(\.rangeValue)
            let length = assistTextSource?.length ?? (textView.string as NSString).length
            // A text edit that leaves the primary range unchanged (forward-delete at the caret, Replace All
            // further down) also leaves the cache, whose other carets are then past the end of the text.
            if let cached = storedSelectionSet,
               cached.ranges.allSatisfy({ NSMaxRange($0) <= length }),
               cached.ranges == liveRanges || liveRanges == [cached.primaryRange] {
                return cached
            }
            return EditorSelectionSet(selectedRanges: textView.selectedRanges) ??
                EditorSelectionSet(single: selectedRange)
        }
        set {
            cancelPendingExternalViewport()
            isUpdatingSelectionSet = true
            defer { isUpdatingSelectionSet = false }
            storedSelectionSet = newValue
            textView.selectedRanges = newValue.asNSValueArray
            // Verify the write actually survived intact. If AppKit silently
            // collapsed/merged it (only possible when there is more than
            // one range: a single range always round-trips), fall back to
            // showing just the primary natively rather than leaving AppKit
            // in whatever partial/collapsed shape it produced on its own —
            // `storedSelectionSet` above already retains the correct full
            // model regardless. `clampedToLiveText` guards this fallback
            // write itself against an out-of-bounds `primaryRange` (a
            // hostile-review-found gap: this is the property's own safety
            // net and must not itself be able to fail silently).
            if newValue.isMultiple, textView.selectedRanges.map(\.rangeValue) != newValue.ranges {
                textView.selectedRanges = [NSValue(range: clampedToLiveText(newValue.primaryRange))]
            }
            invalidateCurrentLinePresentation()
        }
    }

    /// Called by `EditorView.Coordinator.textViewDidChangeSelection` for
    /// every selection-changed notification the setter above did not itself
    /// post (`isUpdatingSelectionSet` guards that distinction). Clears
    /// `storedSelectionSet` once it no longer matches what `selectionSet`'s
    /// own getter would still trust, so a later coincidental match can never
    /// resurrect it — see `selectionSet`'s own doc comment for the exact
    /// failure this prevents.
    func invalidateStoredSelectionSetIfStale() {
        guard let cached = storedSelectionSet else { return }
        let liveRanges = textView.selectedRanges.map(\.rangeValue)
        guard cached.ranges != liveRanges, liveRanges != [cached.primaryRange] else { return }
        storedSelectionSet = nil
    }
}
