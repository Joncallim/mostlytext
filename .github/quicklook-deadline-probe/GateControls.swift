import Darwin
import Foundation
import Synchronization

@main
struct GateControls {
    static func main() async throws {
        try requireHost()
        let fallback = PreparedReply(kind: .fallback, html: Data("frozen fallback".utf8))
        let rich = PreparedReply(kind: .rich, html: Data("later rich".utf8))
        let gate = DeadlineGate()
        let selected = Mutex(0)
        await withTaskGroup(of: Void.self) { group in
            for number in 0 ..< 64 {
                group.addTask {
                    gate.select(number.isMultiple(of: 2) ? fallback : rich) { selected.withLock { $0 += 1 } }
                }
            }
        }
        precondition(selected.withLock { $0 } == 1)
        let chosen = await gate.value()
        precondition(chosen.html == fallback.html || chosen.html == rich.html)
        precondition(!gate.select(rich))
        let waiting = DeadlineGate()
        let consumer = Task { await waiting.value() }
        await Task.yield()
        precondition(waiting.select(fallback))
        precondition(!waiting.select(rich))
        let consumed = await consumer.value
        precondition(consumed.html == fallback.html)
        let occupancy = RendererOccupancy()
        let lease = try require(occupancy.acquire())
        let terminal = DeadlineGate()
        precondition(terminal.select(fallback))
        // Deliberately wrong caller in the negative control; never an actual renderer outcome.
        if CommandLine.arguments.dropFirst() == ["--refund-on-deadline"] {
            lease.releaseAfterActualWorkerReturn()
        }
        guard occupancy.acquire() == nil else {
            print("DIRECT_CONTROL_REFUSED premature refund while actual worker has not returned")
            exit(42)
        }
        lease.releaseAfterActualWorkerReturn()
        lease.releaseAfterActualWorkerReturn()
        let next = try require(occupancy.acquire())
        precondition(occupancy.acquire() == nil)
        next.releaseAfterActualWorkerReturn()
        print(
            "DIRECT_GATE_CONTROLS passed:64concurrent/one-winner/frozen/late-rejection/charged-occupancy/exact-refund"
        )
    }

    private static func requireHost() throws {
        let account = getpwuid(getuid())
        guard getuid() == 501, geteuid() == getuid(), let account,
              String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              CommandLine.arguments[0] == "/Users/runner/work/_temp/mostlytext-qldeadline/gate-controls"
        else { throw NSError(domain: "HostedGateControls", code: 1) }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "HostedGateControls", code: 2) }
        return value
    }
}
