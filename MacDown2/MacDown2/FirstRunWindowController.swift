import AppKit
import SwiftUI

/// Hosts `FirstRunView` in a plain titled window (not a document window —
/// `WindowController`'s tab-group machinery does not apply here).
///
/// `isReleasedWhenClosed = false` because `WindowCoordinator` holds this
/// controller strongly for exactly as long as the window is open (see
/// `WindowCoordinator+FirstRun.swift`); AppKit must not deallocate the
/// window out from under that reference before `windowWillClose` has a
/// chance to release it.
@MainActor
final class FirstRunWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(
        onStartWriting: @escaping () -> Void,
        onOpenSample: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to MostlyText")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let view = FirstRunView(
            onStartWriting: { [weak self] in
                onStartWriting()
                self?.close()
            },
            onOpenSample: { [weak self] in
                onOpenSample()
                self?.close()
            }
        )
        window.contentView = NSHostingView(rootView: view)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func windowWillClose(_: Notification) {
        onClose()
    }
}
