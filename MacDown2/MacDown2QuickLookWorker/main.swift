import Foundation
import Security

/// The signed service is intentionally dormant until bounded real rendering
/// has its own native acceptance. No document bytes or file URL enter it here.
@objc private protocol QuickLookWorkerBootstrap {
    func health(withReply reply: @escaping (Bool) -> Void)
}

private final class BootstrapHandler: NSObject, QuickLookWorkerBootstrap {
    func health(withReply reply: @escaping (Bool) -> Void) {
        guard let task = SecTaskCreateFromSelf(nil) else {
            reply(false)
            return
        }
        let sandbox = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool
        let network = SecTaskCopyValueForEntitlement(task, "com.apple.security.network.client" as CFString, nil)
        reply(sandbox == true && network == nil)
    }
}

private final class BootstrapListener: NSObject, NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: QuickLookWorkerBootstrap.self)
        connection.exportedObject = BootstrapHandler()
        connection.resume()
        return true
    }
}

private let delegate = BootstrapListener()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
