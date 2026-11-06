import AppKit
import FileCore
import Preview
import Workspace

extension WindowCoordinator {
    var canAllowPreviewResources: Bool {
        guard let controller = currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)
        else { return false }
        return canAllowPreviewResources(in: controller.model)
    }

    func canAllowPreviewResources(in model: WorkspaceModel) -> Bool {
        guard let controller = controllers.first(where: { $0.model === model }),
              !controller.isClosed, let window = controller.window, window.attachedSheet == nil,
              let document = model.activeDocument, supportsPreviewResources(document)
        else { return false }
        return !controller.previewResourceState.hasGrant(for: document)
    }

    func allowPreviewResourcesForCurrentDocument() {
        guard let controller = currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)
        else { return }
        _ = beginPreviewResourceSelection(from: controller)
    }

    /// A Preview button belongs to its own model even when another native window becomes key.
    func allowPreviewResources(in model: WorkspaceModel) {
        guard let controller = controllers.first(where: { $0.model === model }) else { return }
        _ = beginPreviewResourceSelection(from: controller)
    }

    /// Reserve the origin synchronously at command dispatch, before the task or native sheet can yield.
    @discardableResult
    func beginPreviewResourceSelection(
        from controller: WindowController,
        chooseFolder: @escaping @MainActor (NSWindow, URL) async -> PreviewResourceFolderSelection? = { window, url in
            await NSFilePanelProvider(window: window).choosePreviewResourceFolder(near: url)
        }
    ) -> Task<Bool, Never>? {
        let model = controller.model
        let owner = controller.previewResourceState
        guard controllers.contains(where: { $0 === controller }), !controller.isClosed,
              let window = controller.window, window.attachedSheet == nil,
              let document = model.activeDocument, supportsPreviewResources(document),
              let origin = owner.beginSelection(for: document)
        else { return nil }
        return Task { @MainActor [weak self, weak controller] in
            defer { owner.cancelSelection(origin) }
            guard let self, let controller, !Task.isCancelled,
                  selectionIsCurrent(origin, controller: controller) else { return false }
            guard let selection = await chooseFolder(window, origin.documentURL) else { return false }
            guard !Task.isCancelled, selectionIsCurrent(origin, controller: controller) else { return false }
            do {
                try await owner.install(selection, from: origin) { [weak model] in model?.activeDocument }
                return true
            } catch {
                if !Task.isCancelled, selectionIsCurrent(origin, controller: controller) {
                    owner.failSelection(origin)
                }
                return false
            }
        }
    }

    private func selectionIsCurrent(
        _ origin: PreviewResourceWindowState.SelectionOrigin, controller: WindowController
    ) -> Bool {
        guard controllers.contains(where: { $0 === controller }), !controller.isClosed,
              controller.window != nil, let document = controller.model.activeDocument
        else { return false }
        return controller.previewResourceState.isSelectionCurrent(origin, for: document)
    }

    private func supportsPreviewResources(_ document: FileCore.FileDocument) -> Bool {
        guard document.fileURL != nil else { return false }
        switch PreviewRouter.previewKind(for: document.format) {
        case .markdown, .html: return true
        case .jsonOutline, .none: return false
        }
    }
}
