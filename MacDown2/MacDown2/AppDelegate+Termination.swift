import AppKit

extension AppDelegate {
    func applicationWillTerminate(_: Notification) {
        commandServer?.stop()
        themeCatalog?.cancel()
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard normalLaunchReady else { return .terminateCancel }
        coordinator.commandReceiver?.suspendAdmission()
        Task { @MainActor in
            let result = await coordinator.saveSessionForTermination()
            let terminate = coordinator.handleTerminationSessionResult(result)
            if terminate {
                await finishCommandRequestsForTermination()
                await themeCatalog.shutdown()
            } else {
                coordinator.commandReceiver?.resumeAdmission()
            }
            NSApp.reply(toApplicationShouldTerminate: terminate)
        }
        return .terminateLater
    }
}
