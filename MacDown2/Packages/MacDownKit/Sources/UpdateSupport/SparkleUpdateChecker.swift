import Combine
import Sparkle

/// The app owns admission and lifetime. This interface keeps Sparkle outside
/// application commands and exposes availability without leaking Sparkle APIs.
@MainActor
public protocol UpdateChecking: AnyObject {
    var availability: AnyPublisher<Bool, Never> { get }
    func start()
    func checkForUpdates()
}

@MainActor
public final class SparkleUpdateChecker: UpdateChecking {
    private let controller: SPUStandardUpdaterController

    public init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    public var availability: AnyPublisher<Bool, Never> {
        controller.updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
    }

    public func start() {
        controller.startUpdater()
    }

    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
