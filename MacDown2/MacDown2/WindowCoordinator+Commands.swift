import AppKit
import CommandBridge
import FileCore
import Foundation

extension WindowCoordinator {
    private static func commandFailureReason(_ error: FileStoreError) -> CommandOpenFailure.Reason {
        switch error {
        case .fileMissing: .missingFile
        case .encodingDetectionFailed, .decodingFailed: .invalidEncoding
        default: .unreadable
        }
    }

    func makeCommandReceiver() -> CommandApplicationReceiver {
        let receiver = CommandApplicationReceiver { [weak self] input, admission in
            guard let self else { admission.reject(.unavailable); return }
            guard !terminationSaveInProgress else { admission.reject(.unavailable); return }
            await settleLaunchRestoration()
            if let bytes = input.bytes, await !admitCommandStdin(bytes, admission: admission) {
                admission.reject(.recoveryUnavailable)
                return
            }
            if input.request.paths.isEmpty, input.bytes == nil {
                await ensureWindowExistsForReopen()
                guard let controller = controllers.first(where: { !$0.isClosed }),
                      admission.bind(.activation, lifetime: controller.commandDocumentLifetime) else { return }
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
                return
            }
            for (index, path) in input.request.paths.enumerated() {
                guard !terminationSaveInProgress else { admission.fail(.path(index), reason: .unavailable); continue }
                await openDocument(at: URL(fileURLWithPath: path), admitting: { controller in
                    admission.bind(.path(index), lifetime: controller.commandDocumentLifetime)
                }, failed: { error in
                    admission.fail(.path(index), reason: Self.commandFailureReason(error))
                })
            }
        }
        commandReceiver = receiver
        return receiver
    }
}
