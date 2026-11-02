import Foundation
import JSONSupport

public extension RecoveryBuffer {
    /// Never initialize an older recovery owner by ignoring a future ledger
    /// member. This read-only check does not quarantine, repair or rewrite it.
    static func admitsInstallationLedger(_ data: Data) -> Bool {
        guard data.count <= 16 * 1024 * 1024, let text = String(data: data, encoding: .utf8),
              case let .valid(original) = JSONParser.parse(text), case .object = original.value,
              let ledger = try? JSONDecoder().decode(RecoveryFenceLedger.self, from: data),
              let encoded = try? JSONEncoder().encode(ledger), let json = String(data: encoded, encoding: .utf8),
              case let .valid(after) = JSONParser.parse(json) else { return false }
        guard retainsMembers(original, after: after) else { return false }
        for record in ledger.consumedLegacy.values {
            guard !record.fileName.contains("/"), record.fileName != ".", record.fileName != "..",
                  !record.fileName.utf8.contains(0) else { return false }
        }
        for key in ledger.migrations.keys {
            var visited: Set<String> = []
            var current = key
            while let next = ledger.migrations[current] {
                guard visited.insert(current).inserted, visited.count <= 1024 else { return false }
                current = RecoveryLifetime(documentID: next.destinationDocumentID, epoch: next.destinationEpoch)
                    .fenceKey
            }
        }
        return true
    }

    private static func retainsMembers(_ before: JSONNode, after: JSONNode) -> Bool {
        switch (before.value, after.value) {
        case let (.object(left), .object(right)):
            let fields = Dictionary(uniqueKeysWithValues: right.map { ($0.key, $0.value) })
            return left.allSatisfy { field in
                guard let value = fields[field.key] else { return false }
                return retainsMembers(field.value, after: value)
            }
        case let (.array(left), .array(right)):
            // Ledger sets can reorder when encoded; their members are scalar.
            guard left.count == right.count else { return false }
            return !left.contains {
                if case .object = $0.value {
                    return true
                }; return false
            }
        case (.object, _), (.array, _): return false
        default: return true
        }
    }
}
