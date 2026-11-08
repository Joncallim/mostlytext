import Darwin
import Foundation

// Standalone command-line control. It compiles the same WorkerBoundary.swift
// as the private XPC fixture, but does not exercise sandboxed XPC launch.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe-worker",
   let mode = WorkerBoundary.Mode(rawValue: CommandLine.arguments[2]) {
    WorkerBoundary.workerMain(mode)
}

final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var held: WorkerBoundary.Observation?
    private var normal: WorkerBoundary.Observation?

    func set(_ value: WorkerBoundary.Observation, mode: WorkerBoundary.Mode) {
        lock.lock()
        if mode == .held { held = value } else { normal = value }
        lock.unlock()
    }

    func values() -> (WorkerBoundary.Observation?, WorkerBoundary.Observation?) {
        lock.lock()
        defer { lock.unlock() }
        return (held, normal)
    }
}

func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); Darwin._exit(1) }
}

let path = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let box = OutcomeBox()
let group = DispatchGroup()
let first = ProcessInfo.processInfo.systemUptime
group.enter()
DispatchQueue.global().async {
    box.set(WorkerBoundary.run(executable: path, mode: .held, deadline: first + 1.85), mode: .held)
    group.leave()
}
Thread.sleep(forTimeInterval: 1)
let second = ProcessInfo.processInfo.systemUptime
group.enter()
DispatchQueue.global().async {
    box.set(WorkerBoundary.run(executable: path, mode: .normal, deadline: second + 1.85), mode: .normal)
    group.leave()
}
require(group.wait(timeout: .now() + .seconds(4)) == .success, "both requests must settle")
let (maybeHeld, maybeNormal) = box.values()
guard let held = maybeHeld, let normal = maybeNormal else { Darwin._exit(2) }
require(held.result == .timedOut, "held child must time out")
require(normal.result == .completed, "normal child must complete")
require(held.pid > 0 && normal.pid > 0 && held.pid != normal.pid, "distinct child PIDs")
require(held.finished < normal.finished, "normal child must complete after held timeout")
require(held.finished - first <= 2.10, "held deadline must be bounded")
require(normal.finished - second <= 1.85, "normal deadline must be bounded")
require(kill(held.pid, 0) == -1 && errno == ESRCH, "timed-out child must be reaped")
require(kill(normal.pid, 0) == -1 && errno == ESRCH, "normal child must be reaped")
print("PASS: held=\(held.result.rawValue) normal=\(normal.result.rawValue) distinct=1 normalAfterHeld=1 heldDuration=\(held.finished - first) normalDuration=\(normal.finished - second)")
