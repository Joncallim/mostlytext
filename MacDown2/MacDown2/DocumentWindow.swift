import AppKit
import Workspace

/// Document window that routes layout shortcuts to the coordinator when the
/// SwiftUI `Commands` scene does not handle them (e.g. when the placeholder
/// `WindowGroup` window is closed and the scene becomes inactive).
@MainActor
final class DocumentWindow: NSWindow {
    weak var coordinator: WindowCoordinator?
    let usesComponentDocumentProxyFixture = ComponentTestHostPresentation.isCurrentComponentHost
    private var componentRepresentedURL: URL?
    private(set) var componentProxyAssignmentCount = 0

    /// Component tests retain the presentation field without asking the
    /// machine's IconServices to create a proxy widget. Native UI/ordinary
    /// launches use the real NSWindow property, including its Finder behavior.
    var documentRepresentedURL: URL? {
        get {
            usesComponentDocumentProxyFixture ? componentRepresentedURL : representedURL
        }
        set {
            if usesComponentDocumentProxyFixture {
                componentRepresentedURL = newValue
                componentProxyAssignmentCount += 1
            } else {
                representedURL = newValue
            }
        }
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        if Self.shouldRefreshCommandState(for: event) {
            coordinator?.commandStateDidChange()
        }
    }

    /// Ordinary typing leaves the responder chain unchanged and should not
    /// invalidate SwiftUI command menus. Focus-changing mouse/AppKit events,
    /// plus ⌘F/⌃F opening Find, do require a refresh.
    static func shouldRefreshCommandState(for event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .appKitDefined:
            return true
        case .keyDown:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // ⌘F is stock Find; ⌃F is this app's own Find in Document. Both move focus into a text field.
            return (flags.contains(.command) || flags.contains(.control)) && event.charactersIgnoringModifiers == "f"
        default:
            return false
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleLayoutShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handleLayoutShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let requiredModifiers: NSEvent.ModifierFlags = [.command, .option]
        let ignoredModifiers: NSEvent.ModifierFlags = [.capsLock, .numericPad, .help, .function]
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(ignoredModifiers)
        guard flags == requiredModifiers else { return false }

        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1 else { return false }

        switch characters {
        case "1":
            coordinator?.setPreviewLayout(.editorOnly)
            return true
        case "2":
            coordinator?.setPreviewLayout(.split(fraction: 0.5))
            return true
        case "3":
            coordinator?.setPreviewLayout(.previewOnly)
            return true
        default:
            return false
        }
    }
}
