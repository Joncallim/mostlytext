import AppKit
import Foundation

/// Failure observations only; never selects a view, requests layout or loads a resource.
@MainActor
final class PreviewCopyWindowDiagnostics {
    private let enabled = ProcessInfo.processInfo.environment["MOSTLYTEXT_PREVIEW_RESOURCE_TRACE"] == "1"
    private let events = PreviewCopyWindowEventStorage()
    private var tokens: [ObjectIdentifier: NSObjectProtocol] = [:]

    func observe(_ window: NSWindow, host: NSView) {
        guard enabled else { return }
        let windowID = String(describing: ObjectIdentifier(window))
        let hostID = String(describing: ObjectIdentifier(host))
        let events = events
        events.append("observe host=\(hostID) window=\(windowID) uptime=\(ProcessInfo.processInfo.systemUptime)")
        let token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                           object: window, queue: nil) { _ in
            events.append("will-close host=\(hostID) window=\(windowID) uptime=\(ProcessInfo.processInfo.systemUptime)")
            for (index, frame) in Thread.callStackSymbols.prefix(24).enumerated() {
                events.append("close-stack window=\(windowID) index=\(index) \(frame)")
            }
        }
        tokens[ObjectIdentifier(window)] = token
        print("MOUNTED_COPY_WINDOW_OBSERVER_ACTIVE host=\(hostID) window=\(windowID)")
    }

    func stop(_ window: NSWindow) {
        guard let token = tokens.removeValue(forKey: ObjectIdentifier(window)) else { return }
        NotificationCenter.default.removeObserver(token)
        print("MOUNTED_COPY_WINDOW_EVENTS_AT_STOP window=\(ObjectIdentifier(window)) events=\(events.snapshot())")
    }

    func captureFailure(host: NSView, selected: NSView?) {
        guard enabled else { return }
        let windowState = host.window.map { window in
            let delegate = window.delegate.map { String(reflecting: type(of: $0)) } ?? "nil"
            return "window=\(ObjectIdentifier(window)) visible=\(window.isVisible) "
                + "identifier=\(String(describing: window.identifier)) delegate=\(delegate)"
        } ?? "window=nil"
        var snapshots: [String] = []
        var visited = 0
        func visit(_ view: NSView, depth: Int) {
            guard depth <= 20, visited < 128 else { return }
            visited += 1
            if NSStringFromClass(type(of: view)).hasSuffix(".NSTextInteractionView") {
                snapshots.append("view=\(ObjectIdentifier(view)) selected=\(view === selected) "
                    + "hidden=\(view.isHiddenOrHasHiddenAncestor) alpha=\(view.alphaValue) "
                    + "frame=\(view.frame) visibleRect=\(view.visibleRect) "
                    + "windowVisible=\(view.window?.isVisible == true)")
            }
            for child in view.subviews {
                visit(child, depth: depth + 1)
            }
        }
        visit(host, depth: 0)
        let selectedID = selected.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        let state = "host=\(ObjectIdentifier(host)) \(windowState) selected=\(selectedID) "
            + "nativeViews=\(snapshots) priorWindowEvents=\(events.snapshot())"
        print("MOUNTED_COPY_WINDOW_STATE_BEFORE_PROBE \(state)")
    }
}

private final class PreviewCopyWindowEventStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.withLock {
            values.append(String(value.prefix(512)))
            if values.count > 64 {
                values.removeFirst(values.count - 64)
            }
        }
    }

    func snapshot() -> [String] {
        lock.withLock { values }
    }
}
