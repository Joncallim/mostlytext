import ExportService
import Foundation

/// MainActor serializes document publication. A lease's final filesystem
/// cutoff also serializes revocation against primary promotion off-main.
@MainActor
final class ExportDocumentProtectionRegistry {
    private struct Entry {
        let id: UUID
        weak var lease: ExportLifetimeLease?
        let admission: ExportDestinationAdmission
    }

    private var entries: [Entry] = []

    @discardableResult
    func register(_ admission: ExportDestinationAdmission, lease: ExportLifetimeLease) -> UUID {
        entries.removeAll { $0.lease == nil }
        let id = UUID()
        entries.append(Entry(id: id, lease: lease, admission: admission))
        return id
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id || $0.lease == nil }
    }

    func documentsWillPublish(urls: [URL], identities: [ExportProtectedFileIdentity]) {
        entries.removeAll { $0.lease == nil }
        for entry in entries {
            guard let lease = entry.lease else { continue }
            do {
                try entry.admission.checkNoDocumentAliases(urls)
                try entry.admission.checkNoFileAliases(identities)
            } catch {
                lease.revoke()
            }
        }
    }
}
