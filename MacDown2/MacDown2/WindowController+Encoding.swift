import AppKit
import FileCore
import Foundation
import Workspace

@MainActor
extension WindowController {
    func saveDocument(
        withEncoding encoding: FileEncodingMetadata, origin: DocumentActionAuthority? = nil
    ) async {
        guard let origin = origin ?? DocumentActionAuthority(model: model),
              origin.isCurrent(in: self),
              let document = model.activeDocument, document.encoding != encoding else { return }
        await externalFileController.drainRecovery()
        guard origin.isCurrent(in: self) else { return }
        _ = await model.saveWithoutDestinationPrompt(encoding: encoding)
        guard origin.isCurrent(in: self) else { return }
        externalFileController.synchronize(with: model.activeDocument)
        updateTitleAndEditedState()
    }

    func reopenDocument(
        withEncoding encoding: String.Encoding, origin: DocumentActionAuthority? = nil
    ) async {
        // Re-selecting the current encoding is a complete no-op: no recovery
        // drain, disk read, prompt, undo reset or focus change.
        guard let origin = origin ?? DocumentActionAuthority(model: model),
              origin.isCurrent(in: self),
              model.activeDocument?.encoding.encoding != encoding else { return }
        await externalFileController.drainRecovery()
        guard origin.isCurrent(in: self) else { return }
        let result = await externalFileController.reopenWithEncoding(
            encoding,
            confirmDiscardingChanges: { [weak self] document in
                await self?.confirmDiscardingChanges(for: document, encoding: encoding) ?? false
            },
            stillAuthorized: { [weak self] in
                guard let self else { return false }
                return origin.isCurrent(in: self)
            }
        )
        guard origin.isCurrent(in: self) else { return }
        if case .unreadable = result {
            presentReopenFailure(encoding: encoding)
        }
        updateTitleAndEditedState()
    }

    private func confirmDiscardingChanges(for document: FileDocument, encoding: String.Encoding) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let name = document.fileURL?.lastPathComponent ?? String(localized: "Untitled")
        alert.messageText = String(localized: "Discard Unsaved Changes?")
        alert.informativeText = String(
            localized: """
            Reopening \"\(name)\" as \(FileEncodingMetadata(encoding: encoding, bom: .none).displayName) \
            replaces the text in the editor with the file on disk. Your unsaved changes and undo history \
            will be lost.
            """
        )
        alert.addButton(withTitle: String(localized: "Reopen and Discard Changes"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard let window else { return alert.runModal() == .alertFirstButtonReturn }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }

    private func presentReopenFailure(encoding: String.Encoding) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Can't Reopen with This Encoding")
        alert.informativeText = String(
            localized: """
            The file is not valid \(FileEncodingMetadata(encoding: encoding, bom: .none).displayName) text. \
            Nothing was changed; choose another encoding.
            """
        )
        alert.addButton(withTitle: String(localized: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
