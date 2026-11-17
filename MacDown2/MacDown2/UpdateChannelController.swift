import Combine
import Foundation
import UpdateSupport

/// Owns Sparkle only after installation migration has admitted normal app work.
/// Development builds have no update key and therefore never start a feed check.
@MainActor
final class UpdateChannelController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private var updater: (any UpdateChecking)?
    private var availabilityObservation: AnyCancellable?

    func startIfConfigured() {
        guard updater == nil,
              Self.hasReleaseConfiguration(info: Bundle.main.infoDictionary ?? [:]) else { return }

        let checker = SparkleUpdateChecker()
        availabilityObservation = checker.availability
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available in
                self?.canCheckForUpdates = available
            }
        updater = checker
        checker.start()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updater?.checkForUpdates()
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
