import Darwin
import Foundation
import Security

/// Fixed harmless process controls. No authored text, document access or VM execution.
@main
struct FixedWorker {
    static func main() throws {
        let args = CommandLine.arguments
        let account = getpwuid(getuid())
        guard args.count == 4, ["normal", "held"].contains(args[1]),
              let request = Int(args[2]), request > 0,
              let parent = Int32(args[3]), parent > 0, getppid() == parent,
              getuid() == 501, getuid() == geteuid(), let account,
              String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              let task = SecTaskCreateFromSelf(nil),
              SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true,
              SecTaskCopyValueForEntitlement(task, "com.apple.security.inherit" as CFString, nil) as? Bool == true
        else { throw Failure.refused }
        let record: [String: Any] = [
            "request_id": request, "mode": args[1], "pid": getpid(), "ppid": getppid(),
            "sandbox": true, "inherit": true,
        ]
        var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        data.append(10)
        guard data.count < 512 else { throw Failure.refused }
        try FileHandle.standardOutput.write(contentsOf: data)
        if args[1] == "normal" {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .milliseconds(500))
        timer.setEventHandler {
            _ = kill(getpid(), SIGKILL)
            _exit(125)
        }
        timer.resume()
        withExtendedLifetime(timer) {
            while true {
                pause()
            }
        }
    }

    enum Failure: Error { case refused }
}
