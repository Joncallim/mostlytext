import Foundation

/// Shares the primary store's producer lock/key and retains it for the entire
/// companion transaction. Only verified pending state can restore receipts.
final class ExportCompanionJournal {
    private let producer: ExportJournalStore
    let authentication: ExportCompanionAuthentication
    private var previous: Data?
    private var writtenReceipt: ExportOwnedFileReceipt?
    private(set) var pending: ExportCompanionAuthentication.AuthenticatedPending?

    init(producer: ExportJournalStore) throws {
        self.producer = producer
        authentication = try producer.companionAuthentication()
        try producer.checkCompanionCapacity()
        previous = try producer.readCompanionPending()
        pending = try previous.map(authentication.openPending)
    }

    var binding: ExportJournalRecord.Binding {
        producer.companionBinding
    }

    func save(_ record: ExportCompanionPendingRecord) throws {
        let bytes = try authentication.sealPending(record)
        try checkCurrent()
        writtenReceipt = try producer.replaceCompanionPending(bytes, previous: previous)
        previous = bytes
        pending = try authentication.openPending(bytes)
    }

    func receipt(named name: String) throws -> ExportOwnedFileReceipt {
        try checkCurrent()
        guard let pending else { throw ExportError.unsafePublication }
        return try ExportOwnedFileReceipt(authenticatedCompanion: pending.receipt(named: name))
    }

    func finish() throws {
        guard let pending else { return }
        // Recheckpoint an authenticated loaded record before retiring the
        // actual private file; an archived receipt never adopts its inode.
        try save(pending.value)
        guard let writtenReceipt else { throw ExportError.unsafePublication }
        try producer.finishCompanionPending(writtenReceipt)
        previous = nil
        self.writtenReceipt = nil
        self.pending = nil
    }

    func checkCurrent() throws {
        try producer.checkCurrent()
        guard try producer.readCompanionPending() == previous else { throw ExportError.unsafePublication }
    }
}
