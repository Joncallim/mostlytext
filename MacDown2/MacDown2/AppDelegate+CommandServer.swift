import CommandBridge
import Foundation

extension AppDelegate {
    func scheduleCommandServerStart() {
        guard !Self.launchArguments.contains("-UITesting"),
              !SingleTestInstanceGuard.isRunningUnderXCTest else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.settleLaunchRestoration()
            guard commandServer == nil, let identity = Bundle.main.bundleIdentifier,
                  let location = try? CommandEndpointLocation.forCurrentUser(productIdentity: identity) else { return }
            commandServer = CommandApplicationServer(location: location, receiver: coordinator.makeCommandReceiver())
        }
    }

    func finishCommandRequestsForTermination() async {
        coordinator.commandReceiver?.finishForTermination()
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while let commandServer, commandServer.activeConnections > 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        commandServer?.stop()
    }
}
