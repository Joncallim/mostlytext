import AppKit
import SwiftUI

/// Identifies the empty scene's own window without claiming unrelated windows.
struct StartupPlaceholderView: NSViewRepresentable {
    func makeNSView(context _: Context) -> StartupPlaceholderMarkerView {
        StartupPlaceholderMarkerView(frame: .zero)
    }

    func updateNSView(_: StartupPlaceholderMarkerView, context _: Context) {}
}

final class StartupPlaceholderMarkerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        AppDelegate.markSwiftUIPlaceholder(window)
    }
}
