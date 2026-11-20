import AppKit
import FileCore
import Foundation
import Workspace

extension WindowCoordinator {
    /// The active document's encoding in the key window, for menu checkmarks.
    var keyDocumentEncoding: FileEncodingMetadata? {
        _ = commandStateRevision
        return currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)?
            .model.activeDocument?.encoding
    }

    /// Reopen and Save with Encoding both operate on the document's own file,
    /// so they need a usable backing file and no unresolved conflict.
    var keyDocumentSupportsEncodingChange: Bool {
        _ = commandStateRevision
        return currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)?
            .model.activeDocument?.hasEncodableBackingFile == true
    }

    func reopenKeyDocument(withEncoding encoding: String.Encoding) {
        guard let controller = currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow),
              let document = controller.model.activeDocument,
              document.encoding.encoding != encoding,
              let origin = DocumentActionAuthority(model: controller.model)
        else { return }
        Task { await controller.reopenDocument(withEncoding: encoding, origin: origin) }
    }

    func saveKeyDocument(withEncoding encoding: FileEncodingMetadata) {
        guard let controller = currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow),
              let origin = DocumentActionAuthority(model: controller.model)
        else { return }
        Task { await controller.saveDocument(withEncoding: encoding, origin: origin) }
    }

    /// The status-bar encoding actions act on the window that owns the bar —
    /// not whichever window happens to be key when the action runs (#183 R01).
    func reopenDocument(
        in model: WorkspaceModel, withEncoding encoding: String.Encoding, origin: DocumentActionAuthority
    ) {
        guard let controller = controllers.first(where: { $0.model === model }),
              let document = model.activeDocument,
              document.encoding.encoding != encoding,
              origin.isCurrent(in: controller)
        else { return }
        Task { await controller.reopenDocument(withEncoding: encoding, origin: origin) }
    }

    func saveDocument(
        in model: WorkspaceModel, withEncoding encoding: FileEncodingMetadata, origin: DocumentActionAuthority
    ) {
        guard let controller = controllers.first(where: { $0.model === model }),
              origin.isCurrent(in: controller) else { return }
        Task { await controller.saveDocument(withEncoding: encoding, origin: origin) }
    }
}

extension FileDocument {
    var hasEncodableBackingFile: Bool {
        guard fileURL != nil, state != .conflict else { return false }
        if case .unavailable = backingState {
            return false
        }
        return true
    }
}
