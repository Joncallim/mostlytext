import ExportService
import Foundation

/// Retains no window, document or lease. Ordinary inputs can become frozen;
/// the disabled validated path always keeps its strict identity policy.
@MainActor
final class WeakValidatedExportLease {
    weak var lease: ExportLifetimeLease?
    private let ordinary: Bool
    private var frozenTabID: UUID?

    init(_ lease: ExportLifetimeLease, ordinary: Bool) {
        self.lease = lease
        self.ordinary = ordinary
    }

    func didFreezeOrdinaryInputs(tabID: UUID) {
        if ordinary {
            frozenTabID = tabID
        }
    }

    func sourceIdentityWillChange(from oldTab: UUID?, to newTab: UUID?) {
        if let frozen = frozenTabID, oldTab == frozen, newTab == frozen {
            return
        }
        lease?.revoke()
    }

    func sourceScopeWillChange() {
        if frozenTabID == nil {
            lease?.revoke()
        }
    }
}
