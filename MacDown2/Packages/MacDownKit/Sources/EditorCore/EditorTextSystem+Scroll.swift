import AppKit
import QuartzCore

// MARK: - Selection / scroll (session restore seam)

public extension EditorTextSystem {
    /// The current selected range in UTF-16 offsets.
    var selectedRange: NSRange {
        get { textView.selectedRange() }
        set {
            cancelPendingExternalViewport()
            textView.setSelectedRange(newValue)
        }
    }

    /// The current vertical scroll offset of the clip view.
    var scrollOffset: CGFloat {
        get { scrollView?.contentView.bounds.origin.y ?? pendingScrollOffset ?? 0 }
        set {
            cancelPendingExternalViewport()
            pendingScrollOffset = newValue
            applyPendingScrollOffset()
        }
    }

    /// The UTF-16 offset of the character at the top-left of the visible rect.
    ///
    /// Returns `0` when the text view has no layout or is not installed in a
    /// scroll view. This is the editor side of the scroll-sync seam.
    var topVisibleUTF16Offset: Int {
        guard let scrollView else { return 0 }

        let clipOrigin = scrollView.contentView.bounds.origin
        // This is the same clip-view conversion used by the gutter's
        // visible-fragment enumeration. `convert(_:from:)` gives TextKit the
        // lookup coordinates for this mounted editor; subtracting
        // `textContainerInset` here would apply the inset twice and anchor a
        // reload above the reader's actual top line.
        let point = textView.convert(clipOrigin, from: scrollView.contentView)
        guard let fragment = layoutManager.textLayoutFragment(for: point) else {
            return 0
        }
        let documentStart = contentStorage.documentRange.location
        return contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
    }

    /// The complete TextKit paragraphs intersecting the mounted viewport.
    /// A highlighter can use this as a bounded paint request without copying
    /// or scanning the document. Nil means layout cannot establish authority.
    var visibleUTF16Range: NSRange? {
        guard let scrollView else { return nil }
        let clip = scrollView.contentView.bounds
        guard !clip.isEmpty else { return nil }
        let top = textView.convert(clip.origin, from: scrollView.contentView)
        let bottom = textView.convert(NSPoint(x: clip.minX, y: clip.maxY), from: scrollView.contentView)
        guard let first = layoutManager.textLayoutFragment(for: top) else { return nil }
        let start = contentStorage.offset(
            from: contentStorage.documentRange.location, to: first.rangeInElement.location
        )
        let length = textView.textStorage?.length ?? 0
        guard start >= 0, start <= length else { return nil }
        let end: Int
        if let last = layoutManager.textLayoutFragment(for: bottom) {
            end = contentStorage.offset(
                from: contentStorage.documentRange.location, to: last.rangeInElement.endLocation
            )
        } else {
            // The lower edge may be in the blank area below the final text
            // fragment. Walk only a bounded number of nearby fragments and
            // use EOF only when the actual final fragment ends above that
            // edge. An unresolved mid-document layout remains unavailable.
            var finalEnd: Int?
            var count = 0
            layoutManager.enumerateTextLayoutFragments(
                from: first.rangeInElement.location, options: [.ensuresLayout]
            ) { fragment in
                count += 1
                let candidate = contentStorage.offset(
                    from: contentStorage.documentRange.location, to: fragment.rangeInElement.endLocation
                )
                guard count <= 512, candidate >= start,
                      candidate - start <= 65536,
                      candidate <= length,
                      fragment.layoutFragmentFrame.maxY <= bottom.y
                else { return false }
                if candidate == length {
                    finalEnd = candidate
                    return false
                }
                return true
            }
            guard let finalEnd else { return nil }
            end = finalEnd
        }
        guard end >= start, end <= length else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// Scrolls the given UTF-16 range into the visible rect.
    ///
    /// This is a thin seam over `NSTextView.scrollRangeToVisible(_:)` so the
    /// app target can drive editor scroll from the preview without depending
    /// on AppKit directly.
    ///
    /// Callers build the range from a *parsed* document's `SourceMap`, which
    /// trails the live text by up to one debounce interval. Delete a trailing
    /// section and sync inside that window and the range runs past the end of
    /// the text, so it is clamped here.
    ///
    /// Measured on macOS 26.6, `NSTextView.scrollRangeToVisible(_:)` clamps
    /// such a range internally rather than raising — so this is not a crash
    /// fix, and E08's plan (§2.3) is wrong to describe it as one. It is here
    /// to make the contract explicit and version-independent: a stale range
    /// scrolls to the end of the live text, by this code's decision rather
    /// than by an undocumented AppKit one.
    func scrollToVisible(utf16Range range: NSRange) {
        cancelPendingExternalViewport()
        syncFrameHeightToContent()
        textView.scrollRangeToVisible(clampedToLiveText(range))
    }

    /// Places the selection at `range`, brings it on screen, and optionally
    /// flashes the native find indicator over it (D9 — the outline's jump).
    ///
    /// `range` is clamped to the live text, for the same reason as
    /// `scrollToVisible` above. Order matters: select → ensure layout for the
    /// range → scroll → flash. `showFindIndicator(for:)` draws from laid-out
    /// geometry, so flashing before layout puts it in the wrong place or
    /// drops it silently. `syncFrameHeightToContent()` runs first so the
    /// frame actually has somewhere to scroll into — see its doc comment.
    ///
    /// `animated` drives a short, easing scroll instead of an instant jump —
    /// used by the outline sidebar, where an instant snap read as jarring
    /// for a jump that can span most of the document. It falls back to the
    /// instant `scrollRangeToVisible(_:)` if no scroll view is attached yet
    /// or the target's layout fragment cannot be resolved.
    func revealSelection(utf16Range range: NSRange, flash: Bool, animated: Bool = false) {
        cancelPendingExternalViewport()
        syncFrameHeightToContent()
        let clamped = clampedToLiveText(range)
        textView.setSelectedRange(clamped)
        ensureLayout(for: clamped)

        if animated, let scrollView, let targetFrame = layoutFragmentFrame(atUTF16Location: clamped.location) {
            animateScroll(toY: targetFrame.minY, in: scrollView)
        } else {
            textView.scrollRangeToVisible(clamped)
        }

        if flash {
            textView.showFindIndicator(for: clamped)
        }
    }

    /// Clamps a range built against a stale snapshot to the live text length.
    ///
    /// Uses `NSString.length` — UTF-16 code units, the unit `NSRange` is in.
    /// `String.count` counts Characters and under-clamps on emoji and CJK,
    /// which is exactly where a stale range is most likely to be wrong.
    internal func clampedToLiveText(_ range: NSRange) -> NSRange {
        let length = (textView.string as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = length - location
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }

    /// Duration of the outline sidebar's "reveal heading" scroll animation.
    /// Must match `ScrollSyncController.jumpAnimationDuration` — this module
    /// cannot import Preview to share that constant directly, and the
    /// controller's echo-suppression window during a jump is sized against
    /// it, so a mismatch here would let a mid-animation frame slip through
    /// and be misread as a fresh, genuine scroll.
    private static let jumpAnimationDuration: TimeInterval = 0.2

    /// The layout fragment's frame at `utf16Location`, forcing layout for it
    /// first. `nil` if the location cannot be resolved against the current
    /// content storage. `internal`, not `private`, so tests can verify the
    /// jump animation's target directly rather than through the animation
    /// itself — headless tests have no real display driving `NSAnimationContext`,
    /// so a completed-animation's end state is not something a test can wait
    /// for reliably.
    func layoutFragmentFrame(atUTF16Location utf16Location: Int) -> CGRect? {
        let documentStart = contentStorage.documentRange.location
        guard let location = contentStorage.location(documentStart, offsetBy: utf16Location) else {
            return nil
        }
        var frame: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) { fragment in
            frame = fragment.layoutFragmentFrame
            return false
        }
        return frame
    }

    /// Animates the scroll view's clip view to `targetY`, clamped to the
    /// document's actual scrollable range.
    private func animateScroll(toY targetY: CGFloat, in scrollView: NSScrollView) {
        scrollView.contentView.wantsLayer = true
        let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        let target = NSPoint(x: scrollView.contentView.bounds.origin.x, y: min(max(0, targetY), maxY))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.jumpAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func ensureLayout(for range: NSRange) {
        let documentStart = contentStorage.documentRange.location
        guard let start = contentStorage.location(documentStart, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else {
            return
        }
        layoutManager.ensureLayout(for: textRange)
    }

    /// Applies any pending scroll offset once the text view is inside a scroll
    /// view. Called by ``EditorView`` after mounting the text view.
    internal func applyPendingScrollOffset() {
        guard let scrollView, let offset = pendingScrollOffset else { return }
        var origin = scrollView.contentView.bounds.origin
        origin.y = offset
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pendingScrollOffset = nil
    }

    /// New navigation supersedes both delayed passes from a disk reload.
    /// Keep unrelated session offsets and frame-height synchronization intact.
    internal func cancelPendingExternalViewport() {
        guard pendingExternalViewport != nil else { return }
        pendingExternalViewport = nil
        pendingExternalViewportRevision = nil
        pendingScrollOffset = nil
    }

    internal func cancelExternalViewportForChangedSelection() {
        guard !isPerformingProgrammaticTextUpdate,
              let snapshot = pendingExternalViewport,
              textView.selectedRanges.map(\.rangeValue) != [clampedToLiveText(snapshot.selectedRange)]
        else { return }
        cancelPendingExternalViewport()
    }

    /// Restores a disk-reload viewport only after the replacement has its
    /// current TextKit layout. The captured source location takes precedence
    /// over a raw offset because frame-height changes can otherwise clamp the
    /// old offset and visibly pull the reader upward.
    /// Restores the pending snapshot and returns whether it needs one final
    /// post-selection pass. The second pass consumes the snapshot.
    @discardableResult
    internal func applyPendingExternalViewport() -> Bool {
        guard let snapshot = pendingExternalViewport else { return false }
        guard pendingExternalViewportRevision == editRevision else {
            pendingExternalViewport = nil
            pendingExternalViewportRevision = nil
            // The raw offset belongs to the same superseded disk reload;
            // falling back to it would still move the reader after an edit.
            pendingScrollOffset = nil
            return false
        }
        guard let scrollView else { return false }

        guard let location = snapshot.topVisibleUTF16Offset,
              let frame = layoutFragmentFrame(atUTF16Location: location)
        else {
            pendingExternalViewport = nil
            pendingExternalViewportRevision = nil
            return false
        }

        pendingScrollOffset = nil
        let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        var origin = scrollView.contentView.bounds.origin
        // The lookup point is already converted from the clip view, while
        // the fragment frame itself begins inside NSTextView's vertical inset.
        // Add that inset only when converting the frame back to a clip origin.
        let fragmentOffset = snapshot.topVisibleFragmentOffset ?? 0
        origin.y = min(max(0, frame.minY + textView.textContainerInset.height + fragmentOffset), maxY)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        return true
    }

    /// Brings the frame height up to date off the back of an editing or
    /// caret-movement event, one run-loop turn later.
    ///
    /// Keyboard-driven caret movement and typing are entirely internal to
    /// `NSTextView` — they never flow through SwiftUI's `updateNSView`, so
    /// `syncFrameHeightToContent()` would otherwise never run for those paths
    /// and the frame would fall behind the content again. Cheap on the common
    /// path: the signature check inside no-ops once the frame has caught up.
    ///
    /// Deferred one run-loop turn because the delegate callbacks that drive
    /// this fire *during* `NSTextView`'s own handling, before it has finished
    /// updating its layout; measuring then reads a half-updated state.
    ///
    /// This deliberately does **not** scroll. An earlier version called
    /// `scrollRangeToVisible(selection)` here, which meant every selection
    /// change — including ones the user never initiated — yanked the viewport
    /// back to the caret, so scrolling away from the caret and releasing
    /// snapped straight back to it. `NSTextView` already scrolls to follow the
    /// caret on its own; all it ever needed from us was a frame tall enough
    /// to have somewhere to scroll to.
    func scheduleFrameHeightSync() {
        frameSyncTask?.cancel()
        frameSyncTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            syncFrameHeightToContent()
            let needsExternalViewportSettle = applyPendingExternalViewport()
            let externalViewportRevision = pendingExternalViewportRevision
            applyPendingScrollOffset()

            // Setting a replacement selection can trigger NSTextView's own
            // deferred visibility adjustment. Restore one more time after
            // that run-loop turn, but only if this is still the same disk
            // replacement; a later edit/reload must never inherit it.
            guard needsExternalViewportSettle else { return }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  externalViewportRevision == editRevision
            else { return }
            syncFrameHeightToContent()
            _ = applyPendingExternalViewport()
            pendingExternalViewport = nil
            pendingExternalViewportRevision = nil
        }
    }
}
