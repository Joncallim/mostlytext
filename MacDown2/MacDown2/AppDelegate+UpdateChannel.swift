extension AppDelegate {
    func startUpdateChannelIfPermitted() {
        guard !Self.launchArguments.contains("-UITesting"), !SingleTestInstanceGuard.isRunningUnderXCTest else {
            return
        }
        updateChannel.startIfConfigured()
    }
}
