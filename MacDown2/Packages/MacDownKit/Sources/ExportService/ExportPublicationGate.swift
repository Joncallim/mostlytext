import Foundation

/// In-process serialization only. The opened directory identity covers case
/// aliases and same-stem outputs without guessing filesystem name folding.
enum ExportPublicationGate {
    private struct Key: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    private final class Entry {
        let gate = NSLock()
        var users = 0
    }

    private final class Table: @unchecked Sendable {
        let lock = NSLock()
        var entries: [Key: Entry] = [:]
    }

    private static let table = Table()

    static func withDirectory<T>(device: UInt64, inode: UInt64, _ operation: () throws -> T) rethrows -> T {
        let key = Key(device: device, inode: inode)
        let entry = table.lock.withLock {
            let entry = table.entries[key] ?? Entry()
            entry.users += 1
            table.entries[key] = entry
            return entry
        }
        entry.gate.lock()
        defer {
            entry.gate.unlock()
            table.lock.withLock {
                entry.users -= 1
                if entry.users == 0 {
                    table.entries.removeValue(forKey: key)
                }
            }
        }
        return try operation()
    }
}
