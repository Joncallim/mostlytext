import Darwin
import Foundation
import OSLog
import Security

@objc(QLXPCCapabilityService) protocol QLXPCCapabilityService {
    func ping(_ requestID: NSNumber, withReply reply: @escaping (NSString, NSNumber, NSNumber, NSNumber) -> Void)
}

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
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: QLXPCCapabilityService.self)
        connection.exportedObject = PingHandler()
        connection.resume()
        return true
    }
}

private let delegate = ListenerDelegate()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
