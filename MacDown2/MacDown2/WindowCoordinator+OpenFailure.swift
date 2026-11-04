import AppKit
import FileCore
import Foundation

/// A human-readable description of a failed file open. `FileStoreError`
/// itself has no `LocalizedError` conformance, so this app boundary maps its
/// typed failure cases to presentation text. Associated decoding diagnostics
/// already carry FileCore's package-localised messages. Shared by the failed-open
/// alert and `ContentAreaView`'s empty state so their explanations stay consistent.
enum FileOpenFailurePresentation {
    static func message(for error: FileStoreError) -> String {
        switch error {
        case .fileMissing: String(localized: "The file could not be found.")
        case .permissionDenied: String(localized: "MostlyText does not have permission to read this file.")
        case .notRegularFile: String(localized: "This is not a regular file.")
        case .invalidURL: String(localized: "This is not a valid file location.")
        case .fileChangedDuringRead: String(localized: "The file changed while it was being read. Try again.")
        case .encodingDetectionFailed: String(localized: "The file's text encoding could not be determined.")
        case let .decodingFailed(diagnostics):
            diagnostics.first?.message ?? String(localized: "The file's contents could not be decoded.")
        default: String(localized: "The file could not be read.")
        }
    }
}

/// The failed-open alert for `openDocument(at:)`. Split out of
/// `WindowCoordinator.swift` to stay under the file-length lint budget.
///
/// `openDocument(at:)` can fail before any window/controller exists for the
/// document — there is nothing else in the app that would ever tell the user
/// a Finder double-click, a Dock drop, or a launch-argument file silently
/// failed to open, so this presents the real reason rather than the app
/// doing nothing.
extension WindowCoordinator {
    func presentOpenFailure(_ error: FileStoreError, url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't Open \"\(url.lastPathComponent)\"")
        alert.informativeText = FileOpenFailurePresentation.message(for: error)
        // Bytes that are neither BOM-marked nor valid UTF-8 and that detection
        // cannot identify unambiguously: offer the explicit choice instead of a
        // dead end (never a lossy guess).
        let offersEncoding = error.isUndecodableText
        alert.addButton(withTitle: String(localized: "OK"))
        if offersEncoding {
            alert.addButton(withTitle: String(localized: "Open With Encoding…"))
        }
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard offersEncoding, response == .alertSecondButtonReturn else { return }
            Task { @MainActor [weak self] in await self?.openDocumentChoosingEncoding(at: url) }
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }
}
