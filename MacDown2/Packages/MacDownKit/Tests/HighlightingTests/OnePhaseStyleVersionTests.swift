import Foundation
#if canImport(Neon)
    @testable import Neon
#else
    @testable import OwnedStylingCore
#endif
import RangeState
import Testing

@MainActor
@Suite("One-phase style results retain content version ownership", .serialized)
struct OnePhaseStyleVersionTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["", "xyz", "longer replacement"],
          [TokenApplication.Action.apply, .replace])
    func changedContentRejectsAwaitedStyles(replacement: String, action: TokenApplication.Action) async throws {
        let system = OnePhaseTextSystem()
        let gate = OnePhaseTokenGate()
        let application = oldApplication(action)
        let provider = TokenProvider(syncValue: { _ in nil }, mainActorAsyncValue: { _ in
            await gate.suspend()
            return application
        })
        let validator = TokenSystemValidator(textSystem: system, tokenProvider: provider)
        let request = VersionedRange(NSRange(location: 0, length: 3), version: system.content.currentVersion)
        let operation = Task { @MainActor in
            await validator.validationProvider.async(isolation: MainActor.shared, request)
        }
        defer { gate.release() }
        var started = gate.started.stream.makeAsyncIterator()
        _ = try #require(await started.next())
        system.content.string = replacement
        gate.release()
        let result = await operation.value
        #expect(result == .stale)
        #expect(system.applications.isEmpty, "obsolete token results must never reach the style interface")
    }

    @Test(.timeLimit(.minutes(1)), arguments: [TokenApplication.Action.apply, .replace])
    func unchangedContentAppliesAwaitedStylesOnce(action: TokenApplication.Action) async throws {
        let system = OnePhaseTextSystem()
        let gate = OnePhaseTokenGate()
        let application = oldApplication(action)
        let provider = TokenProvider(syncValue: { _ in nil }, mainActorAsyncValue: { _ in
            await gate.suspend()
            return application
        })
        let validator = TokenSystemValidator(textSystem: system, tokenProvider: provider)
        let request = VersionedRange(NSRange(location: 0, length: 3), version: system.content.currentVersion)
        let operation = Task { @MainActor in
            await validator.validationProvider.async(isolation: MainActor.shared, request)
        }
        defer { gate.release() }
        var started = gate.started.stream.makeAsyncIterator()
        _ = try #require(await started.next())
        gate.release()
        let result = await operation.value
        #expect(result == .success(request.value))
        #expect(system.applications == [application])
    }

    @Test(arguments: ["", "xyz", "longer replacement"], [TokenApplication.Action.apply, .replace])
    func synchronousReentrantEditRejectsStyles(replacement: String, action: TokenApplication.Action) {
        let system = OnePhaseTextSystem()
        let application = oldApplication(action)
        let provider = TokenProvider(syncValue: { _ in
            system.content.string = replacement
            return application
        }, mainActorAsyncValue: { _ in application })
        let validator = TokenSystemValidator(textSystem: system, tokenProvider: provider)
        let request = VersionedRange(NSRange(location: 0, length: 3), version: system.content.currentVersion)
        #expect(validator.validationProvider.sync(request) == .stale)
        #expect(system.applications.isEmpty)
    }

    @Test(arguments: [TokenApplication.Action.apply, .replace])
    func unchangedSynchronousContentAppliesOnce(action: TokenApplication.Action) {
        let system = OnePhaseTextSystem()
        let application = oldApplication(action)
        let provider = TokenProvider(syncValue: { _ in application }, mainActorAsyncValue: { _ in application })
        let validator = TokenSystemValidator(textSystem: system, tokenProvider: provider)
        let request = VersionedRange(NSRange(location: 0, length: 3), version: system.content.currentVersion)
        #expect(validator.validationProvider.sync(request) == .success(request.value))
        #expect(system.applications == [application])
    }

    @Test func alreadyObsoleteRequestsSkipBothProviders() async {
        let system = OnePhaseTextSystem()
        var providerCalls = 0
        let provider = TokenProvider(syncValue: { _ in
            providerCalls += 1
            return .noChange
        }, mainActorAsyncValue: { _ in
            providerCalls += 1
            return .noChange
        })
        let validator = TokenSystemValidator(textSystem: system, tokenProvider: provider)
        let request = VersionedRange(NSRange(location: 0, length: 3), version: system.content.currentVersion)
        system.content.string = "new"
        #expect(validator.validationProvider.sync(request) == .stale)
        let result = await validator.validationProvider.async(isolation: MainActor.shared, request)
        #expect(result == .stale)
        #expect(providerCalls == 0)
        #expect(system.applications.isEmpty)
    }

    private func oldApplication(_ action: TokenApplication.Action) -> TokenApplication {
        TokenApplication(tokens: [Token(name: "old-content", range: NSRange(location: 0, length: 3))],
                         range: NSRange(location: 0, length: 3), action: action)
    }
}

private final class OnePhaseContent: VersionedContent {
    private(set) var currentVersion = 0
    var string = "abc" {
        didSet { currentVersion += 1 }
    }

    func length(for version: Int) -> Int? {
        version == currentVersion ? string.utf16.count : nil
    }
}

@MainActor
private final class OnePhaseTextSystem: TextSystemInterface {
    let content = OnePhaseContent()
    private(set) var applications: [TokenApplication] = []

    func applyStyles(for application: TokenApplication) {
        applications.append(application)
    }
}

@MainActor
private final class OnePhaseTokenGate {
    let started = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.continuation.yield(())
        }
    }

    func release() {
        let waiting = continuation
        continuation = nil
        waiting?.resume()
    }
}
