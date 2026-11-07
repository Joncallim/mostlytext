#if DEBUG || RELEASE_PREVIEW_PROBE
    import Foundation

    /// Hosted-only bounded observations. These records never decide admission, scheduling or test success.
    enum PreviewResourceDiagnostics {
        private final class Storage: @unchecked Sendable {
            let lock = NSLock()
            var events: [String] = []
            var sequence = 0
        }

        private static let storage = Storage()
        private static let enabled = ProcessInfo.processInfo.environment["MOSTLYTEXT_PREVIEW_RESOURCE_TRACE"] == "1"

        static func record(_ event: String, context: PreviewResourceLoad?, detail: String = "") {
            guard enabled else { return }
            let contextID = context?.id.uuidString ?? "none"
            let revoked = context?.isRevoked ?? true
            let cancelled = Task.isCancelled
            storage.lock.withLock {
                storage.sequence += 1
                storage.events
                    .append(
                        "\(storage.sequence) \(event) load=\(contextID) revoked=\(revoked) "
                            + "cancelled=\(cancelled) \(detail)"
                    )
                if storage.events.count > 256 {
                    storage.events.removeFirst(storage.events.count - 256)
                }
            }
        }

        static var isEnabled: Bool {
            enabled
        }

        static func dump(_ label: String) {
            print("PREVIEW_RESOURCE_TRACE label=\(label) enabled=\(enabled) events=\(snapshot())")
        }

        static func snapshot() -> String {
            guard enabled else { return "resource trace disabled" }
            return storage.lock.withLock { storage.events.joined(separator: " | ") }
        }
    }
#endif
