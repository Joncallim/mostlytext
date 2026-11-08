import Darwin
import Foundation

/// Private hosted fixture only. A request owns exactly one unreaped child PID;
/// no timeout path can terminate the XPC service or another request's worker.
enum WorkerBoundary {
    enum Mode: String {
        case held
        case normal
    }

    enum Result: String {
        case completed
        case timedOut
        case launchFailed
        case failed
    }

    struct Observation {
        let result: Result
        let pid: pid_t
        let started: Double
        let finished: Double
    }

    /// The worker receives no document bytes or paths. Its argument is a
    /// closed, fixed mode, and the executable is the signed service itself.
    static func run(executable: URL, mode: Mode, deadline: Double,
                    onSpawn: ((pid_t, Double) -> Void)? = nil) -> Observation {
        let started = ProcessInfo.processInfo.systemUptime
        guard executable.isFileURL, executable.path.hasSuffix("/QLReplyProbeXPCService"),
              deadline > started else {
            return Observation(result: .launchFailed, pid: 0, started: started,
                               finished: ProcessInfo.processInfo.systemUptime)
        }
        let words = [executable.path, "--probe-worker", mode.rawValue]
        let arguments = words.map { strdup($0) } + [nil]
        defer { arguments.forEach { free($0) } }
        var child: pid_t = 0
        let spawnError = arguments.withUnsafeBufferPointer { buffer in
            posix_spawn(&child, executable.path, nil, nil,
                        UnsafeMutablePointer(mutating: buffer.baseAddress!), environ)
        }
        guard spawnError == 0, child > 0 else {
            return Observation(result: .launchFailed, pid: 0, started: started,
                               finished: ProcessInfo.processInfo.systemUptime)
        }
        onSpawn?(child, ProcessInfo.processInfo.systemUptime)
        // This request is the only reaper for this PID. A child that exits
        // between WNOHANG and kill remains a zombie, so its PID cannot be
        // reused before this request reaps it.
        while true {
            var status: Int32 = 0
            let waited = waitpid(child, &status, WNOHANG)
            if waited == child {
                // Darwin's C wait macros are not imported into Swift. A
                // zero wait status is exactly a clean exit with code zero.
                let clean = status == 0
                return Observation(result: clean ? .completed : .failed, pid: child,
                                   started: started, finished: ProcessInfo.processInfo.systemUptime)
            }
            if waited == -1 {
                if errno == EINTR { continue }
                return Observation(result: .failed, pid: child, started: started,
                                   finished: ProcessInfo.processInfo.systemUptime)
            }
            let now = ProcessInfo.processInfo.systemUptime
            if now >= deadline {
                // The exact child remains unreaped. Never signal a process
                // group, the XPC service, or a PID owned by another request.
                _ = kill(child, SIGKILL)
                while waitpid(child, &status, 0) == -1 && errno == EINTR {}
                return Observation(result: .timedOut, pid: child, started: started,
                                   finished: ProcessInfo.processInfo.systemUptime)
            }
            Thread.sleep(forTimeInterval: min(0.01, deadline - now))
        }
    }

    /// Runs only after the fixed command-line shape and sandbox policy are
    /// checked in main.swift. The normal worker stays alive across the held
    /// worker's deadline when the provider starts it one second later.
    static func workerMain(_ mode: Mode) -> Never {
        Thread.sleep(forTimeInterval: mode == .normal ? 1.55 : 10)
        Darwin._exit(0)
    }
}
