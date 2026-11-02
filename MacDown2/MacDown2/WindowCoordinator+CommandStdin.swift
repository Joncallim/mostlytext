import AppKit
import CommandBridge
import FileCore
import Foundation

extension WindowCoordinator {
    /// Stages participate in canonical persistence, not ordinary UI commands.
    var sessionControllers: [WindowController] {
        controllers + commandStdinStages
    }

    func admitCommandStdin(_ bytes: Data, admission: CommandOpeningAdmission) async -> Bool {
        var succeeded = false
        await commandStdinAdmissions.run(key: "stdin") { [self] in
            succeeded = await performCommandStdinAdmission(bytes, admission: admission)
        }
        return succeeded
    }

    private func performCommandStdinAdmission(_ bytes: Data, admission: CommandOpeningAdmission) async -> Bool {
        guard admission.canContinue, !terminationSaveInProgress else { return false }
        let keyWindow = controllers.first(where: { $0.window === NSApp.keyWindow })?.window
        let document: FileCore.FileDocument
        do {
            document = try await CommandStdinDocumentFactory.prepare(bytes, recoveryBuffer: recoveryBuffer)
        } catch { return false }
        guard admission.canContinue, !terminationSaveInProgress else { return false }
        let model = makeWindowModel()
        model.tabStore.newTab(document: document)
        let controller = makeWindowController(model: model)
        let excludedFromWindowMenu = controller.window?.isExcludedFromWindowsMenu ?? false
        controller.window?.isExcludedFromWindowsMenu = true
        commandStdinStages.append(controller)
        sessionPublicationOrder.invalidateCapturedSnapshots()
        defer {
            if commandStdinStages.contains(where: { $0 === controller }) {
                commandStdinStages.removeAll { $0 === controller }
                sessionPublicationOrder.invalidateCapturedSnapshots()
                controller.window?.close()
            }
        }
        guard await saveSessionResult().persisted, admission.canContinue,
              !controller.isClosed, commandStdinStages.contains(where: { $0 === controller }),
              admission.bind(.stdin, lifetime: controller.commandDocumentLifetime) else { return false }
        commandStdinStages.removeAll { $0 === controller }
        controller.window?.isExcludedFromWindowsMenu = excludedFromWindowMenu
        addController(controller, addingAsTab: true, keyWindow: keyWindow, useAmbientWindow: false)
        return true
    }
}
