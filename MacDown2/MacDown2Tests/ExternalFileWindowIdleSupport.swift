import Darwin
import Dispatch
import Foundation
@testable import MacDown2
import Testing

extension ExternalFileWindowOccupancyTests {
    struct IdleBins {
        var interrupt: [UInt64] = []
        var platformIdle: [UInt64] = []
        var elapsedNanoseconds: [UInt64] = []

        var interruptTotal: UInt64 {
            interrupt.reduce(0, +)
        }

        var platformIdleTotal: UInt64 {
            platformIdle.reduce(0, +)
        }

        var elapsedNanosecondsTotal: UInt64 {
            elapsedNanoseconds.reduce(0, +)
        }
    }

    func measureIdleBins(
        controllers: [WindowController], targets: [URL], expectedWatches: Int
    ) async throws -> IdleBins {
        var generations: [UInt] = []
        for controller in controllers {
            await generations.append(controller.externalFileController.monitor.currentRequestGeneration())
        }
        var prior = try processWakeups()
        var priorTime = DispatchTime.now().uptimeNanoseconds
        var bins = IdleBins()
        for _ in 0 ..< 20 {
            try await Task.sleep(for: .seconds(1))
            let current = try processWakeups()
            let currentTime = DispatchTime.now().uptimeNanoseconds
            bins.interrupt.append(current.interrupt - prior.interrupt)
            bins.platformIdle.append(current.platformIdle - prior.platformIdle)
            bins.elapsedNanoseconds.append(currentTime - priorTime)
            prior = current
            priorTime = currentTime
        }
        var after: [UInt] = []
        for controller in controllers {
            await after.append(controller.externalFileController.monitor.currentRequestGeneration())
            #expect(controller.externalFileController.bindRetryAttempt == 0)
        }
        #expect(after == generations, "untouched windows must not schedule monitor probes or debounce")
        #expect(try watcherDescriptors(for: targets).values.allSatisfy { $0 == expectedWatches })
        return bins
    }

    func verifyAtomicReplacement(
        controller: WindowController, source: URL, directory: URL, expected: String
    ) async throws {
        let identity = try #require(controller.model.tabStore.activeTab?.id.uuidString)
        let editor = try #require(controller.editorStore.existingSystem(for: identity))
        let replacement = directory.appendingPathComponent("idle-positive.md")
        try expected.write(to: replacement, atomically: true, encoding: .utf8)
        let retired = try watcherIdentity(for: source)
        guard rename(replacement.path, source.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try await waitUntil(.seconds(5), "atomic replacement after bound idle") {
            controller.model.activeDocument?.text == expected
                && controller.model.activeDocument?.state == .clean
                && editor.textView.string == expected
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == expected)
        try await requireWatcherTransition(
            retired: retired, source: source, directory: directory, stage: "bound idle positive"
        )
    }
}
