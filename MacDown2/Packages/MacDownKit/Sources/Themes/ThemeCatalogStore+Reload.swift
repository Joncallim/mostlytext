import Darwin
import Foundation

extension ThemeCatalogStore {
    private enum Observation {
        case valid(Record)
        case invalid(ThemeCatalogDiagnostic.Problem, signature: String)
    }

    public func reload() throws -> ThemeCatalogState {
        try Task.checkCancellation()
        let present = try directory.identifiers()
        let instant = now()
        let existing = records.keys.sorted { $0.uuidString < $1.uuidString }
        let new = present.filter { records[$0] == nil }
        var nextRecords: [UUID: Record] = [:]
        var nextDiagnostics: [ThemeCatalogDiagnostic] = []
        var nextPending: [UUID: PendingFailure] = [:]
        var signatures: [UUID: String] = [:]
        var recheck = false
        // Retained known-good values consume the same 256-entry budget.
        for id in existing + new {
            try Task.checkCancellation()
            switch observe(id: id) {
            case let .valid(record):
                signatures[id] = String(reflecting: record.bytes.fingerprint)
                if nextRecords.count < ThemeCatalogSnapshot.maximumCustomThemes {
                    nextRecords[id] = record
                } else {
                    nextDiagnostics.append(ThemeCatalogDiagnostic(
                        id: id,
                        problem: .catalogFull,
                        pendingConfirmation: false
                    ))
                }
            case let .invalid(problem, signature):
                signatures[id] = signature
                let failure = pending[id].flatMap { $0.signature == signature ? $0 : nil }
                    ?? PendingFailure(signature: signature, firstSeen: instant)
                let retain = records[id] != nil && failure.firstSeen.duration(to: instant) < .milliseconds(750)
                if retain, let record = records[id] {
                    nextRecords[id] = record
                    nextPending[id] = failure
                    recheck = true
                }
                nextDiagnostics.append(ThemeCatalogDiagnostic(id: id, problem: problem, pendingConfirmation: retain))
            }
        }
        nextDiagnostics.sort { $0.id.uuidString < $1.id.uuidString }
        try directory.checkRoot()
        let changed = records != nextRecords || diagnostics != nextDiagnostics || observations != signatures
        guard !changed || catalog.revision < UInt64.max - 2 else { throw ThemeCatalogError.staleImportPlan }
        let next = try ThemeCatalogSnapshot(revision: catalog.revision + (changed ? 1 : 0),
                                            customThemes: nextRecords.values.map(\.file))
        records = nextRecords
        diagnostics = nextDiagnostics
        pending = nextPending
        observations = signatures
        catalog = next
        needsRecheck = recheck
        return currentState()
    }

    private func observe(id: UUID) -> Observation {
        let name = ThemeDirectory.name(for: id)
        let stored: ThemeStoredBytes
        do {
            stored = try directory.read(name)
        } catch let ThemeStorageError.unavailable(code) where code == ENOENT {
            return .invalid(.missingFile, signature: "missing")
        } catch {
            return .invalid(.unreadableFile, signature: metadataSignature(name))
        }
        do {
            let file = try ThemeFile.decode(stored.bytes)
            guard file.stableID == id else {
                return .invalid(.invalidTheme, signature: stored.fingerprint.digest)
            }
            return .valid(Record(file: file, bytes: stored))
        } catch { return .invalid(.invalidTheme, signature: stored.fingerprint.digest) }
    }

    private func metadataSignature(_ name: String) -> String {
        var info = stat()
        guard fstatat(directory.descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return "errno:\(errno)" }
        return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"
            + ":\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec):\(info.st_mode):\(info.st_nlink)"
    }
}
