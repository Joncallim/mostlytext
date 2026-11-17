import Combine
import Foundation
import Sparkle

/// Owns Sparkle only after installation migration has admitted normal app work.
/// Development builds have no update key and therefore never start a feed check.
@MainActor
final class UpdateChannelController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private var updaterController: SPUStandardUpdaterController?
    private var availabilityObservation: AnyCancellable?

    func startIfConfigured() {
        guard updaterController == nil,
              Self.hasReleaseConfiguration(info: Bundle.main.infoDictionary ?? [:]) else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        availabilityObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available in
                self?.canCheckForUpdates = available
            }
        updaterController = controller
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController?.checkForUpdates(nil)
    }

    static func hasReleaseConfiguration(info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String,
              feed == "https://mostlytext.app/appcast.xml",
              let publicKey = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: publicKey)?.count == 32,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SURequireSignedFeed"] as? Bool == true
        else { return false }
        return true
    }
}
