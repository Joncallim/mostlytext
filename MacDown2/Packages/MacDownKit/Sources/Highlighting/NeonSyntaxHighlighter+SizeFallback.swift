import AppKit
import Neon

/// Register row H5's bounded, size-based highlighting fallback.
///
/// - The decision uses `NSTextStorage.length` (UTF-16 code units, O(1)); the
///   document is never rescanned or converted to UTF-8 per edit.
/// - Open, restore, reload and language changes go through
///   ``configure(languageID:)``, which does not build a parser for an oversized
///   document. Growth while open (typing, paste, replace-all, undo/redo,
///   external replacement, IME) goes through the ``HighlightingStorageGate``,
///   which withholds the crossing edit from Neon before Neon's reparse.
/// - Full highlighting returns only after the document is back at or below the
///   policy's lower restore threshold and idle (hysteresis), never mid-edit.
extension NeonSyntaxHighlighter {
    /// Highlighter-owned rendering attributes: exactly what the attribute
    /// provider sets. Selection, marked text, find highlights and the
    /// document's own attributes are not rendering attributes Neon owns.
    static let highlighterAttributeKeys: [NSAttributedString.Key] = [.foregroundColor, .font, .underlineStyle]

    func installGate() {
        gate.shouldForwardEdit = { [weak self] length in
            self?.shouldForwardEdit(postEditLength: length) ?? false
        }
        gate.didProcessCharacterEdit = { [weak self] length in
            self?.didProcessCharacterEdit(postEditLength: length)
        }
        if let storage = textSystem.textView.textStorage {
            gate.install(on: storage)
        }
    }

    /// (Re)evaluates the effective mode for `languageID` from scratch: drops
    /// any attached highlighter, then builds one only if the language has a
    /// grammar and the document is within the language's size policy.
    func configure(languageID: String?) {
        guard !isTornDown else { return }
        restoreTask?.cancel()
        restoreTask = nil
        let hadViewport = stopViewport()
        if discardHighlighter() || hadViewport {
            clearHighlighterPresentation()
        }
        guard let config = registry.configuration(for: languageID) else {
            setMode(.plain)
            return
        }
        if let policy = policyProvider(languageID), documentLength > policy.reduceAboveUTF16Units {
            let reason = HighlightingState.Reason.documentTooLarge(limitUTF16Units: policy.reduceAboveUTF16Units)
            setMode(startViewport() ? .visibleOnly(reason) : .reduced(reason))
            return
        }
        setMode(buildHighlighter(config: config) ? .full : .plain)
    }

    var documentLength: Int {
        textSystem.textView.textStorage?.length ?? 0
    }

    /// Drops Neon's highlighter and makes its in-flight work inert (its
    /// attribute provider checks ``generation``). Returns false if none was
    /// attached.
    @discardableResult
    func discardHighlighter() -> Bool {
        gate.downstream = nil
        guard highlighter != nil else { return false }
        repaintDeadline = 0
        generation &+= 1
        highlighter = nil
        return true
    }

    // MARK: - Gate callbacks (inside NSTextStorage.processEditing)

    private func shouldForwardEdit(postEditLength: Int) -> Bool {
        guard highlighter != nil else { return false }
        guard let policy = policyProvider(languageID), postEditLength > policy.reduceAboveUTF16Units else {
            return true
        }
        restoreTask?.cancel()
        restoreTask = nil
        discardHighlighter()
        setMode(.reduced(.documentTooLarge(limitUTF16Units: policy.reduceAboveUTF16Units)))
        // Not now: this runs inside the storage's `processEditing`. Queued on
        // the main queue, so it also runs after any `endBuffering` Neon queued
        // for an earlier edit (whose late styling is inert by generation).
        let clearGeneration = generation
        DispatchQueue.main.async { [weak self] in
            // Skipped if a highlighter was rebuilt meanwhile (it owns the
            // presentation again).
            guard let self, !isTornDown, generation == clearGeneration else { return }
            clearHighlighterPresentation()
            if let policy = policyProvider(languageID), documentLength > policy.reduceAboveUTF16Units,
               startViewport() {
                setMode(.visibleOnly(.documentTooLarge(limitUTF16Units: policy.reduceAboveUTF16Units)))
            }
        }
        return false
    }

    private func didProcessCharacterEdit(postEditLength: Int) {
        guard state.isReduced, let policy = policyProvider(languageID) else { return }
        restoreTask?.cancel()
        restoreTask = nil
        if postEditLength <= policy.restoreAtOrBelowUTF16Units {
            scheduleRestore(after: policy.restoreIdleDelay)
        } else if viewportModeEnabled, languageID == "markdown", viewportSession == nil,
                  postEditLength > policy.reduceAboveUTF16Units,
                  postEditLength <= Self.viewportMaxUTF16Units {
            scheduleRestore(after: policy.restoreIdleDelay)
        }
    }

    private func scheduleRestore(after delay: Duration) {
        let restoreSleep = restoreSleep
        restoreTask = Task { @MainActor [weak self] in
            if let restoreSleep {
                try? await restoreSleep(delay)
            } else {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            restoreTask = nil
            restoreIfStillEligible(retryDelay: delay)
        }
    }

    private func restoreIfStillEligible(retryDelay: Duration) {
        guard state.isReduced, let policy = policyProvider(languageID),
              documentLength <= policy.restoreAtOrBelowUTF16Units
              || (viewportModeEnabled && languageID == "markdown" && viewportSession == nil
                  && documentLength > policy.reduceAboveUTF16Units
                  && documentLength <= Self.viewportMaxUTF16Units)
        else { return }
        // Never rebuild under an active IME composition; try again later.
        if textSystem.textView.hasMarkedText() {
            scheduleRestore(after: retryDelay)
            return
        }
        // Native finding: after this restore Neon's first pass of rendering attributes was applied but TextKit did
        // not repaint until the next edit. Ask for a repaint after each pass of styling for a short while.
        if documentLength <= policy.restoreAtOrBelowUTF16Units {
            repaintDeadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        }
        configure(languageID: languageID)
    }

    // MARK: - Presentation

    /// Asks TextKit to repaint the rendering attributes once the current pass of styling has finished.
    func requestRepaintIfNeeded() {
        guard !repaintScheduled, DispatchTime.now().uptimeNanoseconds < repaintDeadline else { return }
        repaintScheduled = true
        let scheduledGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            repaintScheduled = false
            guard generation == scheduledGeneration, highlighter != nil else { return }
            repaintRenderingAttributes()
        }
    }

    func repaintRenderingAttributes() {
        let textView = textSystem.textView
        // Never touch the storage during an IME composition; the next styling pass in the window tries again.
        guard !textView.hasMarkedText() else { return }
        // An attribute-only edit notification makes TextKit redraw the range. (`invalidateRenderingAttributes` would
        // discard the attributes Neon just applied.) No characters change, so Neon ignores it, nothing is undoable
        // and the document is not marked as edited.
        if let storage = textView.textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
            storage.endEditing()
        }
        textView.needsDisplay = true
        repaintCount &+= 1
    }

    /// Removes the rendering attributes the highlighter sets (colour, font,
    /// underline) across the document, leaving any marked (IME) text alone.
    /// Rendering attributes are presentation only: the text, its storage
    /// attributes, undo and selection are untouched, and no storage edit (so
    /// no delegate callback or notification loop) results.
    func clearHighlighterPresentation() {
        let textView = textSystem.textView
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }
        let length = documentLength
        var ranges = [NSRange(location: 0, length: length)]
        if textView.hasMarkedText() {
            let marked = textView.markedRange()
            ranges = [
                NSRange(location: 0, length: min(marked.location, length)),
                NSRange(location: NSMaxRange(marked), length: max(0, length - NSMaxRange(marked))),
            ]
        }
        let origin = contentManager.documentRange.location
        for range in ranges where range.length > 0 {
            guard let start = contentManager.location(origin, offsetBy: range.location),
                  let end = contentManager.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end)
            else { continue }
            for key in Self.highlighterAttributeKeys {
                layoutManager.removeRenderingAttribute(key, for: textRange)
            }
        }
        presentationClearCount += 1
        lastPresentationClearUptime = DispatchTime.now().uptimeNanoseconds
    }
}
