import Darwin
import Foundation
import QuickLookSource

/// One selected descriptor, one child, one monotonic deadline and one reaper.
/// A blocked regular-file read cannot retain an extension or service thread.
enum SourceProcess {
    struct Result {
        let data: Data?
        let status: QuickLookWorkerStatus
    }

    private static let seconds = 3.0
    private static let maximumOutputBytes = QuickLookSourceFallback.maximumSourceBytes * 6 + 4096

    static func run(selectedDescriptor: Int32) -> Result {
        guard let executable = Bundle.main.executableURL,
              executable.path.hasSuffix("/MostlyTextQuickLookWorker")
        else { return Result(data: nil, status: .failed) }
        guard let output = makeOutput() else { return Result(data: nil, status: .failed) }
        defer { close(output) }
        guard let child = spawn(executable: executable, source: selectedDescriptor, output: output) else {
            return Result(data: nil, status: .failed)
        }
        return awaitChild(child, output: output)
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

    private static func spawn(executable: URL, source: Int32, output: Int32) -> pid_t? {
        // Stable high-numbered inputs avoid dup2 order clobbering fd 3 or 4.
        let sourceInput = fcntl(source, F_DUPFD_CLOEXEC, 5)
        guard sourceInput >= 0 else { return nil }
        defer { close(sourceInput) }
        let outputInput = fcntl(output, F_DUPFD_CLOEXEC, 5)
        guard outputInput >= 0 else { return nil }
        defer { close(outputInput) }

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_adddup2(&actions, sourceInput, 3) == 0,
              posix_spawn_file_actions_adddup2(&actions, outputInput, 4) == 0
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

    private static func awaitChild(_ child: pid_t, output: Int32) -> Result {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while true {
            var status: Int32 = 0
            let waited = waitpid(child, &status, WNOHANG)
            if waited == child {
                guard status == 0 else { return Result(data: nil, status: .failed) }
                return readOutput(output)
            }
            if waited == -1 {
                if errno == EINTR {
                    continue
                }
                return Result(data: nil, status: .failed)
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 {
                _ = kill(child, SIGKILL)
                while waitpid(child, &status, 0) == -1, errno == EINTR {}
                return Result(data: nil, status: .timedOut)
            }
            Thread.sleep(forTimeInterval: min(remaining, 0.01))
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
