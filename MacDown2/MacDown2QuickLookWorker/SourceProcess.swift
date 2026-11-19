import Darwin
import Dispatch
import Foundation
import QuickLookBoundary

/// One selected descriptor, one child, one monotonic deadline and one reaper.
/// A blocked regular-file read cannot retain an extension reply or service
/// request thread. At most two background reapers can remain pending.
enum SourceProcess {
    struct Result {
        let data: Data?
        let status: QuickLookWorkerStatus
    }

    private struct Outputs {
        let fallback: Int32
        let derived: Int32
        let combined: Int32
        let marker: Int32
    }

    private struct CompletionState {
        let fallback: Bool
        let derived: Bool
        let combined: Bool
    }

    private static let seconds = 3.0
    private static let maximumOutputBytes = QuickLookSourceBudget.maximumHTMLBytes
    private static let childSlots = ChildSlots()

    static func run(selectedDescriptor: Int32, executable: URL? = Bundle.main.executableURL) -> Result {
        guard let executable,
              executable.path.hasSuffix("/MostlyTextQuickLookWorker")
        else { return Result(data: nil, status: .failed) }
        guard let fallback = makeOutput() else { return Result(data: nil, status: .failed) }
        defer { close(fallback) }
        guard let derived = makeOutput() else { return Result(data: nil, status: .failed) }
        defer { close(derived) }
        guard let combined = makeOutput() else { return Result(data: nil, status: .failed) }
        defer { close(combined) }
        guard let fallbackReady = makeOutput() else { return Result(data: nil, status: .failed) }
        defer { close(fallbackReady) }
        let outputs = Outputs(fallback: fallback, derived: derived, combined: combined, marker: fallbackReady)
        guard childSlots.claim() else { return Result(data: nil, status: .failed) }
        guard let child = spawn(executable: executable, source: selectedDescriptor, outputs: outputs) else {
            childSlots.release()
            return Result(data: nil, status: .failed)
        }
        return awaitChild(child, outputs: outputs)
    }

    private static func makeOutput() -> Int32? {
        var template = Array((FileManager.default.temporaryDirectory
                .appendingPathComponent("mostlytext-ql-source-XXXXXX").path).utf8CString)
        let output = mkstemp(&template)
        guard output >= 0 else { return nil }
        guard unlink(template) == 0 else {
            close(output)
            return nil
        }
        return output
    }

    private static func spawn(executable: URL, source: Int32, outputs: Outputs) -> pid_t? {
        // Stable high-numbered inputs avoid dup2 clobbering fd 3 through 7.
        let sourceInput = fcntl(source, F_DUPFD_CLOEXEC, 8)
        guard sourceInput >= 0 else { return nil }
        defer { close(sourceInput) }
        let fallbackInput = fcntl(outputs.fallback, F_DUPFD_CLOEXEC, 8)
        guard fallbackInput >= 0 else { return nil }
        defer { close(fallbackInput) }
        let derivedInput = fcntl(outputs.derived, F_DUPFD_CLOEXEC, 8)
        guard derivedInput >= 0 else { return nil }
        defer { close(derivedInput) }
        let combinedInput = fcntl(outputs.combined, F_DUPFD_CLOEXEC, 8)
        guard combinedInput >= 0 else { return nil }
        defer { close(combinedInput) }
        let readyInput = fcntl(outputs.marker, F_DUPFD_CLOEXEC, 8)
        guard readyInput >= 0 else { return nil }
        defer { close(readyInput) }

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_adddup2(&actions, sourceInput, 3) == 0,
              posix_spawn_file_actions_adddup2(&actions, fallbackInput, 4) == 0,
              posix_spawn_file_actions_adddup2(&actions, derivedInput, 5) == 0,
              posix_spawn_file_actions_adddup2(&actions, readyInput, 6) == 0,
              posix_spawn_file_actions_adddup2(&actions, combinedInput, 7) == 0
        else { return nil }
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0 else {
            return nil
        }
        let words = [executable.path, "--source-worker"]
        let arguments = words.map { strdup($0) } + [nil]
        defer { arguments.forEach { free($0) } }
        var child: pid_t = 0
        let launched = arguments.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return EINVAL }
            return posix_spawn(&child, executable.path, &actions, &attributes,
                               UnsafeMutablePointer(mutating: base), environ)
        }
        return launched == 0 && child > 0 ? child : nil
    }

    private static func awaitChild(_ child: pid_t, outputs: Outputs) -> Result {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while true {
            var status: Int32 = 0
            let waited = waitpid(child, &status, WNOHANG)
            if waited == child {
                childSlots.release()
                if status == 0 {
                    if let preferred = completedDerived(outputs) {
                        return preferred
                    }
                    return completedFallback(outputs)
                        ?? Result(data: nil, status: .failed)
                }
                return completedDerived(outputs)
                    ?? completedFallback(outputs)
                    ?? Result(data: nil, status: .failed)
            }
            if waited == -1 {
                if errno == EINTR {
                    continue
                }
                if errno == ECHILD {
                    childSlots.release()
                } else {
                    killAndReap(child)
                }
                return completedDerived(outputs)
                    ?? completedFallback(outputs)
                    ?? Result(data: nil, status: .failed)
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 {
                killAndReap(child)
                return completedDerived(outputs)
                    ?? completedFallback(outputs)
                    ?? Result(data: nil, status: .timedOut)
            }
            Thread.sleep(forTimeInterval: min(remaining, 0.01))
        }
    }

    private static func completionState(_ marker: Int32) -> CompletionState {
        var stamp = stat()
        guard fstat(marker, &stamp) == 0, stamp.st_mode & S_IFMT == S_IFREG,
              (1 ... 3).contains(stamp.st_size)
        else { return CompletionState(fallback: false, derived: false, combined: false) }
        var ready = [UInt8](repeating: 0, count: Int(stamp.st_size))
        let readCount = ready.withUnsafeMutableBytes { bytes in
            pread(marker, bytes.baseAddress, bytes.count, 0)
        }
        guard readCount == ready.count, ready[0] == 0x46 else {
            return CompletionState(fallback: false, derived: false, combined: false)
        }
        if ready.count == 1 { return CompletionState(fallback: true, derived: false, combined: false) }
        guard ready[1] == 0x44 else { return CompletionState(fallback: false, derived: false, combined: false) }
        return CompletionState(fallback: true, derived: true, combined: ready.count == 3 && ready[2] == 0x47)
    }

    private static func completedDerived(_ outputs: Outputs) -> Result? {
        let state = completionState(outputs.marker)
        if state.combined {
            let result = readOutput(outputs.combined)
            if result.status == .complete { return result }
        }
        guard state.derived else { return nil }
        let result = readOutput(outputs.derived)
        return result.status == .complete ? result : nil
    }

    private static func completedFallback(_ outputs: Outputs) -> Result? {
        guard completionState(outputs.marker).fallback else { return nil }
        let result = readOutput(outputs.fallback)
        return result.status == .complete ? result : nil
    }

    private static func killAndReap(_ child: pid_t) {
        _ = kill(child, SIGKILL)
        // A kernel-stuck child can outlive SIGKILL. Never block the reply
        // while reaping it, and retain its capacity slot until it exits.
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            while true {
                let reaped = waitpid(child, &status, 0)
                if reaped == child || (reaped == -1 && errno == ECHILD) {
                    childSlots.release()
                    return
                }
                if reaped == -1, errno == EINTR {
                    continue
                }
                return // Unknown wait failure keeps the slot reserved.
            }
        }
    }

    private static func readOutput(_ descriptor: Int32) -> Result {
        var stamp = stat()
        guard fstat(descriptor, &stamp) == 0, stamp.st_mode & S_IFMT == S_IFREG,
              stamp.st_size > 0, stamp.st_size <= maximumOutputBytes
        else { return Result(data: nil, status: .failed) }
        var bytes = Data(count: Int(stamp.st_size))
        let complete = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let count = pread(descriptor, base.advanced(by: offset), buffer.count - offset, off_t(offset))
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        return complete ? Result(data: bytes, status: .complete) : Result(data: nil, status: .failed)
    }
}

/// A timed-out child keeps its slot until the background reaper confirms exit.
/// Two unkillable children therefore fail later requests promptly instead of
/// accumulating blocked reaper threads or retaining XPC reply threads.
private final class ChildSlots: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0

    func claim() -> Bool {
        lock.withLock {
            guard active < 2 else { return false }
            active += 1
            return true
        }
    }

    func release() {
        lock.withLock { active -= 1 }
    }
}
