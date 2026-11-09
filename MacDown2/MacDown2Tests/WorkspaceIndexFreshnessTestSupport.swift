import AppKit
import Foundation
@testable import MacDown2
@testable import TextSearch
import Workspace

@MainActor
struct ControllerFixture {
    let controller: WindowController
    let coordinator: WindowCoordinator
    let defaults: UserDefaults
    let suiteName: String
    let stateDirectory: URL

    func waitForIndexedPath(_ path: String) async -> Bool {
        for _ in 0 ..< 200 {
            let paths = await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath))
            if paths.contains(path) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func retire() {
        coordinator.removeController(controller)
        controller.close()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: stateDirectory)
    }
}

final class IndexWalkProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var walkCount = 0
    private var completedWalkCount = 0
    private var heldRoot: URL?
    private let unavailableRoot: URL?
    private let unavailableWalkNumber: Int?
    private let gate: IndexWalkGate?
    private let gatesByWalk: [Int: IndexWalkGate]
    private var hasHeldWalk = false
    private var reportedUnavailability = false
    private let holdEveryWalk: Bool

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return walkCount
    }

    var completedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completedWalkCount
    }

    var injectedUnavailabilityWasObserved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reportedUnavailability
    }

    init(
        heldRoot: URL? = nil,
        unavailableRoot: URL? = nil,
        unavailableWalkNumber: Int? = nil,
        gate: IndexWalkGate? = nil,
        gatesByWalk: [Int: IndexWalkGate] = [:],
        holdEveryWalk: Bool = false
    ) {
        self.heldRoot = heldRoot?.standardizedFileURL
        self.unavailableRoot = unavailableRoot?.standardizedFileURL
        self.unavailableWalkNumber = unavailableWalkNumber
        self.gate = gate
        self.gatesByWalk = gatesByWalk
        self.holdEveryWalk = holdEveryWalk
    }

    func makeIndex() -> WorkspaceFileIndex {
        WorkspaceFileIndex(walk: { [self] root, excluded in
            let shouldHold: Bool
            let selectedGate: IndexWalkGate?
            lock.lock()
            walkCount += 1
            let walkNumber = walkCount
            selectedGate = gatesByWalk[walkNumber] ?? gate
            shouldHold = root.standardizedFileURL == heldRoot
                && (gatesByWalk[walkNumber] != nil || holdEveryWalk || !hasHeldWalk)
            if shouldHold, !holdEveryWalk {
                hasHeldWalk = true
            }
            lock.unlock()
            if shouldHold {
                selectedGate?.blockUntilReleased()
            }
            let result = try DirectoryWalker().walk(root: root, excludedDirectoryNames: excluded)
            lock.lock()
            completedWalkCount += 1
            lock.unlock()
            return result
        }, simulatedUnavailability: { [self] root in
            lock.lock()
            defer { lock.unlock() }
            guard root.standardizedFileURL == unavailableRoot,
                  unavailableWalkNumber == nil || completedWalkCount == unavailableWalkNumber
            else { return nil }
            reportedUnavailability = true
            return "The folder cannot be read."
        })
    }
}
