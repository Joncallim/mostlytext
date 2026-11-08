import Darwin
import Foundation
import OSLog
import Security

@objc(QLXPCCapabilityService) protocol QLXPCCapabilityService {
    func ping(_ requestID: NSNumber, withReply reply: @escaping (NSString, NSNumber, NSNumber, NSNumber) -> Void)
    func hold(_ requestID: NSNumber, withReady ready: @escaping (NSString, NSNumber, NSNumber, NSNumber) -> Void)
    func render(_ requestID: NSNumber, mode: NSString,
                withReply reply: @escaping (NSString, NSNumber, NSNumber, NSNumber, NSNumber) -> Void)
}

private final class WorkerReply: @unchecked Sendable {
    let call: (NSString, NSNumber, NSNumber, NSNumber, NSNumber) -> Void
    init(_ call: @escaping (NSString, NSNumber, NSNumber, NSNumber, NSNumber) -> Void) {
        self.call = call
    }
}

/// One held operation per service process. The fixture's ping may precede it,
/// but a second hold cannot share the process or extend the watchdog deadline.
private final class HoldAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

private let holdAdmission = HoldAdmission()

private final class PingHandler: NSObject, QLXPCCapabilityService {
    private let logger = Logger(subsystem: "app.mostlytext.qljscprobe", category: "service")
    private let lock = NSLock()
    private var seenRequests: Set<Int64> = []

    func ping(_ requestID: NSNumber, withReply reply: @escaping (NSString, NSNumber, NSNumber, NSNumber) -> Void) {
        let id = requestID.int64Value
        lock.lock()
        let first = seenRequests.insert(id).inserted
        lock.unlock()
        guard id > 0, first,
              let task = SecTaskCreateFromSelf(nil),
              SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true,
              SecTaskCopyValueForEntitlement(task, "com.apple.security.network.client" as CFString, nil) == nil
        else {
            logger.error("QL_XPC_SERVICE refused id=\(id) pid=\(getpid())")
            reply("REFUSED", requestID, NSNumber(value: getpid()), NSNumber(value: 0))
            return
        }
        logger.notice("QL_XPC_SERVICE replied id=\(id) pid=\(getpid()) sandbox=1")
        reply("MOSTLYTEXT_QL_XPC_PING_OK", requestID, NSNumber(value: getpid()), NSNumber(value: 1))
    }

    func hold(_ requestID: NSNumber, withReady ready: @escaping (NSString, NSNumber, NSNumber, NSNumber) -> Void) {
        let id = requestID.int64Value
        lock.lock()
        let first = seenRequests.insert(id).inserted
        lock.unlock()
        guard id > 0, first,
              let task = SecTaskCreateFromSelf(nil),
              SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true,
              SecTaskCopyValueForEntitlement(task, "com.apple.security.network.client" as CFString, nil) == nil,
              holdAdmission.claim()
        else {
            logger.error("QL_XPC_HOLD service-refused id=\(id) pid=\(getpid())")
            ready("REFUSED", requestID, NSNumber(value: getpid()), NSNumber(value: 0))
            return
        }
        let armedAt = ProcessInfo.processInfo.systemUptime
        let deadline = armedAt + 4
        let watchdogStarted = DispatchSemaphore(value: 0)
        let serviceLogger = logger
        Thread.detachNewThread {
            watchdogStarted.signal()
            while true {
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                if remaining <= 0 {
                    break
                }
                Thread.sleep(forTimeInterval: min(remaining, 0.1))
            }
            let expiredAt = ProcessInfo.processInfo.systemUptime
            serviceLogger
                .notice(
                    "QL_XPC_HOLD service-watchdog-expired id=\(id) pid=\(getpid()) at=\(expiredAt)"
                )
            Darwin._exit(124)
        }
        // A ready reply must never precede a running watchdog thread.
        guard watchdogStarted.wait(timeout: .now() + .seconds(1)) == .success else {
            Darwin._exit(125)
        }
        logger.notice("QL_XPC_HOLD service-watchdog-armed id=\(id) pid=\(getpid()) at=\(armedAt) deadline=\(deadline)")
        logger.notice("QL_XPC_HOLD service-ready id=\(id) pid=\(getpid()) sandbox=1")
        ready("MOSTLYTEXT_QL_XPC_HOLD_READY", requestID, NSNumber(value: getpid()), NSNumber(value: 1))
        // Ignore connection loss in the work thread; only the independently
        // armed service watchdog is allowed to end this fixed held operation.
        logger
            .notice(
                "QL_XPC_HOLD service-hold-start id=\(id) pid=\(getpid()) at=\(ProcessInfo.processInfo.systemUptime)"
            )
        Thread.sleep(forTimeInterval: 10)
        logger.notice("QL_XPC_HOLD service-released id=\(id) pid=\(getpid())")
    }

    func render(_ requestID: NSNumber, mode: NSString,
                withReply reply: @escaping (NSString, NSNumber, NSNumber, NSNumber, NSNumber) -> Void) {
        let id = requestID.int64Value
        lock.lock()
        let first = seenRequests.insert(id).inserted
        lock.unlock()
        let servicePID = getpid()
        guard id > 0, first,
              let workerMode = WorkerBoundary.Mode(rawValue: mode as String),
              let executable = Bundle.main.executableURL,
              let task = SecTaskCreateFromSelf(nil),
              SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true,
              SecTaskCopyValueForEntitlement(task, "com.apple.security.network.client" as CFString, nil) == nil
        else {
            logger.error("QL_WORKER_BOUNDARY refused id=\(id) service=\(servicePID)")
            reply("REFUSED", requestID, NSNumber(value: servicePID), NSNumber(value: 0), NSNumber(value: 0))
            return
        }
        let admitted = ProcessInfo.processInfo.systemUptime
        let deadline = admitted + 1.85
        logger.notice("QL_WORKER_BOUNDARY admitted id=\(id) mode=\(workerMode.rawValue, privacy: .public) service=\(servicePID) at=\(admitted) deadline=\(deadline)")
        let callback = WorkerReply(reply)
        let serviceLogger = logger
        Thread.detachNewThread {
            let observed = WorkerBoundary.run(executable: executable, mode: workerMode, deadline: deadline) { child, at in
                serviceLogger.notice("QL_WORKER_BOUNDARY spawned id=\(id) mode=\(workerMode.rawValue, privacy: .public) service=\(servicePID) worker=\(child) at=\(at)")
            }
            serviceLogger.notice("QL_WORKER_BOUNDARY finished id=\(id) mode=\(workerMode.rawValue, privacy: .public) service=\(servicePID) worker=\(observed.pid) result=\(observed.result.rawValue, privacy: .public) at=\(observed.finished)")
            callback.call(observed.result.rawValue as NSString, requestID,
                          NSNumber(value: servicePID), NSNumber(value: observed.pid), NSNumber(value: 1))
        }
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: QLXPCCapabilityService.self)
        connection.exportedObject = PingHandler()
        connection.resume()
        return true
    }
}

if CommandLine.arguments.count > 1 {
    guard CommandLine.arguments.count == 3,
          CommandLine.arguments[1] == "--probe-worker",
          let mode = WorkerBoundary.Mode(rawValue: CommandLine.arguments[2]),
          let task = SecTaskCreateFromSelf(nil),
          SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true,
          SecTaskCopyValueForEntitlement(task, "com.apple.security.network.client" as CFString, nil) == nil
    else { Darwin._exit(126) }
    WorkerBoundary.workerMain(mode)
}
private let delegate = ListenerDelegate()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
