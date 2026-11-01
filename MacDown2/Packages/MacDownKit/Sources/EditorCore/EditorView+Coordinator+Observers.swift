import AppKit

// MARK: - Scroll/undo NotificationCenter observers

// Extracted from `EditorView.swift` to keep that file under its line-count
// limit, mirroring the established per-feature extension-file precedent.

extension EditorView.Coordinator {
    @objc @MainActor func userDidScroll(_ notification: Notification) {
        guard let system, notification.object as AnyObject === system.scrollView else { return }
        system.cancelPendingExternalViewport()
    }

    @objc @MainActor func scrollViewDidScroll(_: Notification) {
        guard let system else { return }
        onScrollChange?(system.topVisibleUTF16Offset)
    }

    @objc @MainActor func editorLayoutDidChange(_: Notification) {
        onLayoutChange?()
    }

    @MainActor func editorAttachmentDidChange() {
        onLayoutChange?()
    }

    /// `EditorTextSystem` itself keeps `lineIndex` correct across undo/redo
    /// (see its own `registerUndoRedoObservers()`); this coordinator-level
    /// observer exists only to redraw the gutter, which `EditorTextSystem`
    /// has no reference to.
    @objc @MainActor func undoManagerDidChange(_ notification: Notification) {
        // Registered with `object: nil` (see `registerCoordinatorObservers`'s
        // doc comment), so this fires for every text system's undo/redo in
        // the app — filter to this one's current (freshly-resolved, not
        // cached) undo manager.
        guard let system, notification.object as AnyObject === system.undoManager else { return }
        gutterView?.updateThickness()
        publishTextAfterUndoRedo(of: system)
    }

    /// TextKit 2 applies an undo/redo without posting `NSText.didChangeNotification`, so
    /// `textDidChange` never ran: the binding (and with it the document model, Save, Preview,
    /// the outline and the recovery buffer) kept the pre-undo text — and the next `updateNSView`
    /// pushed that stale text back into the view, silently redoing the undo.
    @MainActor private func publishTextAfterUndoRedo(of system: EditorTextSystem) {
        guard !isApplyingModelText,
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
        system.scheduleFrameHeightSync()
    }
}

extension EditorView {
    /// Observes scroll changes through the clip view's bounds (NSScrollView
    /// always owns a contentView, so the object is non-optional), plus
    /// undo/redo so the gutter can redraw — `EditorTextSystem` itself keeps
    /// `lineIndex` correct across undo/redo (see its
    /// `registerUndoRedoObservers()`); this coordinator only needs to know
    /// when to invalidate the gutter, which lives at this UI layer.
    ///
    /// The undo/redo observers register with `object: nil` (any sender)
    /// rather than `system.undoManager` evaluated here: at this point
    /// (called from `makeNSView`, before SwiftUI has attached the returned
    /// `NSScrollView` to a window) `system.textView.window` is still nil,
    /// so `EditorTextSystem.undoManager` resolves to its temporary
    /// `fallbackUndoManager` — a different object than the real window
    /// undo manager it switches to once actually mounted. An observer
    /// registered against that stale fallback would never see a real
    /// undo/redo notification (this exact bug was already found and fixed
    /// for `EditorTextSystem`'s OWN line-index-correctness observer, in
    /// `EditorTextSystem+LineIndex.swift` — it just hadn't been applied
    /// here too). `Coordinator.undoManagerDidChange(_:)` re-resolves
    /// `system.undoManager` fresh and checks the notification's sender
    /// against it instead.
    func registerCoordinatorObservers(scrollView: NSScrollView, coordinator: Coordinator) {
        // This denotes user scrolling, including legacy mice which may omit
        // willStart/didEnd. Layout/restoration bounds changes are informational.
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.userDidScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
        scrollView.documentView?.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.editorLayoutDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.documentView
        )
        coordinator.onLayoutChange?()
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.undoManagerDidChange(_:)),
            name: .NSUndoManagerDidUndoChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.undoManagerDidChange(_:)),
            name: .NSUndoManagerDidRedoChange,
            object: nil
        )
    }
}
