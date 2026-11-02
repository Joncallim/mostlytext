@testable import FileCore
import Foundation
import Testing

@Suite("Document file monitor callback lifetime")
@MainActor
struct DocumentFileMonitorCallbackLifetimeTests {
    @Test func cancelReleasesCallbacksBeforeARetiredEventProbeDrains() async throws {
        let url = URL(fileURLWithPath: "/tmp/epic18/callback-lifetime.md")
        let initial = snapshot("initial", at: url)
        let late = DocumentFileObservation.available(snapshot("late", at: url))
        let prober = CallbackLifetimeProber(initial: initial, late: late)
        let watcher = MonitorWatcher()
        let monitor = DocumentFileMonitor(
            debounce: .zero, watcher: watcher, prober: prober, sleeper: { _ in }
        )
        let observations = ObservationRecorder()
        let contexts = ContextRecorder()
        let health = HealthRecorder()

        do {
            // The helper must return: an unfinished bind's async argument stack could itself retain callbacks.
            let captures = try await bindCapturingCallbacks(
                monitor, to: url, observations: observations, contexts: contexts, health: health
            )
            captures.expectRetained()
            #expect(observations.values == [.available(initial)])
            #expect(contexts.count == 1)
            #expect(health.last == .healthy)
            let originalContexts = contexts.values
            let generation = await monitor.generation

            // Direct actor ingress avoids the fake watcher's extra unstructured delivery task.
            await monitor.received(.changed, generation: generation)
            await waitUntil { await prober.isHeld }
            try #require(await prober.isHeld)
            let sequence = await monitor.currentRequestGeneration()

            await monitor.cancel()
            let cancelledSequence = await monitor.currentRequestGeneration()
            #expect(captures.observation.isReleased)
            #expect(captures.health.isReleased)
            #expect(captures.context.isReleased, "cancel must release onContext while the monitor is still alive")
            #expect(watcher.cancelCount == 1)
            #expect(await prober.isHeld, "cancelling publication must not pretend the underlying probe drained")

            // The prober deliberately ignores task cancellation until explicitly released.
            await prober.release()
            await waitUntil { await monitor.probesInFlight.isEmpty }
            try #require(await monitor.probesInFlight.isEmpty)
            // Exercise stale publication and watcher ingress with acknowledged actor calls, not a quiet-time wait.
            await monitor.emit(late, generation: generation, sequence: sequence)
            await monitor.received(.changed, generation: generation)
            #expect(await monitor.currentRequestGeneration() == cancelledSequence)
            #expect(await prober.callCount == 2)
            #expect(observations.values == [.available(initial)])
            #expect(contexts.values == originalContexts)
            #expect(health.last == .healthy)
            await monitor.cancel()
        } catch {
            // Idempotent release also covers a future observe call that has not entered its gate yet.
            await monitor.cancel()
            await prober.release()
            await waitUntil { await monitor.probesInFlight.isEmpty }
            throw error
        }
    }

    private func bindCapturingCallbacks(
        _ monitor: DocumentFileMonitor, to url: URL,
        observations: ObservationRecorder, contexts: ContextRecorder, health: HealthRecorder
    ) async throws -> MonitorCallbackCaptures {
        let observation = MonitorCallbackCapture<DocumentFileObservation> { observations.append($0) }
        let context = MonitorCallbackCapture<DocumentFileObservationContext> { contexts.append($0) }
        let healthCapture = MonitorCallbackCapture<DocumentFileMonitorHealth> { health.append($0) }
        let captures = MonitorCallbackCaptures(
            observation: WeakMonitorCapture(observation), context: WeakMonitorCapture(context),
            health: WeakMonitorCapture(healthCapture)
        )
        try await monitor.bind(
            to: url, priorFileObjectID: nil,
            onObservation: { [observation] in observation.call($0) },
            onHealthChange: { [healthCapture] in healthCapture.call($0) },
            onContext: { [context] in context.call($0) }
        )
        return captures
    }
}

@MainActor
private struct MonitorCallbackCaptures {
    let observation: WeakMonitorCapture
    let context: WeakMonitorCapture
    let health: WeakMonitorCapture

    func expectRetained() {
        #expect(!observation.isReleased)
        #expect(!context.isReleased)
        #expect(!health.isReleased)
    }
}

private final class MonitorCallbackCapture<Value: Sendable>: Sendable {
    private let callback: @Sendable (Value) -> Void

    init(callback: @escaping @Sendable (Value) -> Void) {
        self.callback = callback
    }

    func call(_ value: Value) {
        callback(value)
    }
}

@MainActor
private final class WeakMonitorCapture {
    private weak var value: AnyObject?

    init(_ value: AnyObject) {
        self.value = value
    }

    var isReleased: Bool {
        value == nil
    }
}

private actor CallbackLifetimeProber: DocumentFileProbing {
    private let initial: FileSnapshot
    private let late: DocumentFileObservation
    private var held: CheckedContinuation<DocumentFileObservation, Never>?
    private var released = false
    private(set) var callCount = 0

    init(initial: FileSnapshot, late: DocumentFileObservation) {
        self.initial = initial
        self.late = late
    }

    var isHeld: Bool {
        held != nil
    }

    func observe(
        expectedURL _: URL, priorFileObjectID _: PhysicalFileIdentity.FileObjectID?, decoding _: FileDecodingPolicy
    ) async -> DocumentFileObservation {
        callCount += 1
        guard callCount > 1 else { return .available(initial) }
        guard !released else { return late }
        return await withCheckedContinuation { held = $0 }
    }

    func release() {
        released = true
        let continuation = held
        held = nil
        continuation?.resume(returning: late)
    }
}
