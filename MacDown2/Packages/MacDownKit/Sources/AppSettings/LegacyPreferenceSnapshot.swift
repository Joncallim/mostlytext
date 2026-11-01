import CoreFoundation
import CryptoKit
import Foundation

/// A bounded, immutable copy of one explicitly supplied original-MacDown preference domain.
/// Creating a snapshot does not read UserDefaults or apply any preference to MostlyText.
public struct LegacyPreferenceSnapshot: Sendable, Equatable {
    public static let maximumBytes = 1_048_576
    public static let maximumEntries = 2048
    public static let maximumStringBytes = 4096
    public static let maximumDepth = 8

    public let values: [String: LegacyPreferenceValue]
    /// SHA-256 of the sorted, typed snapshot encoding. Recompute with the same admission
    /// rules before applying a future import plan; this is not a hash of a plist file.
    public let canonicalDigest: String

    public init(domain: [String: Any]) throws {
        var budget = AdmissionBudget()
        var admitted: [String: LegacyPreferenceValue] = [:]
        for key in domain.keys.sorted() {
            try budget.addEntry()
            try budget.addString(key)
            guard let value = domain[key] else { throw LegacyPreferenceSnapshotError.unsupportedValue }
            admitted[key] = try LegacyPreferenceValue.admit(value, depth: 0, budget: &budget)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let canonical = try encoder.encode(admitted)
        guard canonical.count <= Self.maximumBytes else { throw LegacyPreferenceSnapshotError.tooLarge }
        values = admitted
        canonicalDigest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }
}

public enum LegacyPreferenceSnapshotError: Error, Equatable {
    case tooLarge
    case tooManyEntries
    case stringTooLong
    case tooDeep
    case unsupportedValue
    case invalidNumber
}

/// Property-list values are retained as data only. In particular, Data is never unarchived,
/// and a stored URL or path is not converted into a filesystem grant.
public indirect enum LegacyPreferenceValue: Codable, Sendable, Equatable {
    case boolean(Bool)
    case number(type: String, value: String)
    case string(String)
    case data(Data)
    case date(TimeInterval)
    case array([LegacyPreferenceValue])
    case dictionary([String: LegacyPreferenceValue])

    fileprivate static func admit(_ object: Any, depth: Int, budget: inout AdmissionBudget) throws -> Self {
        guard depth <= LegacyPreferenceSnapshot.maximumDepth else { throw LegacyPreferenceSnapshotError.tooDeep }
        if let value = object as? String {
            try budget.addString(value)
            return .string(value)
        }
        if let value = object as? Data {
            try budget.addBytes(value.count)
            return .data(value)
        }
        if let value = object as? Date {
            let seconds = value.timeIntervalSince1970
            guard seconds.isFinite else { throw LegacyPreferenceSnapshotError.invalidNumber }
            try budget.addBytes(MemoryLayout<TimeInterval>.size)
            return .date(seconds)
        }
        if let value = object as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                try budget.addBytes(1)
                return .boolean(value.boolValue)
            }
            guard value.doubleValue.isFinite else { throw LegacyPreferenceSnapshotError.invalidNumber }
            let spelling = value.stringValue
            try budget.addBytes(spelling.utf8.count)
            return .number(type: String(cString: value.objCType), value: spelling)
        }
        return try admitCollection(object, depth: depth, budget: &budget)
    }

    private static func admitCollection(_ object: Any, depth: Int, budget: inout AdmissionBudget) throws -> Self {
        if let value = object as? [Any] {
            var elements: [Self] = []
            for element in value {
                try budget.addEntry()
                try elements.append(admit(element, depth: depth + 1, budget: &budget))
            }
            return .array(elements)
        }
        if let value = object as? [String: Any] {
            var elements: [String: Self] = [:]
            for key in value.keys.sorted() {
                try budget.addEntry()
                try budget.addString(key)
                guard let element = value[key] else { throw LegacyPreferenceSnapshotError.unsupportedValue }
                elements[key] = try admit(element, depth: depth + 1, budget: &budget)
            }
            return .dictionary(elements)
        }
        throw LegacyPreferenceSnapshotError.unsupportedValue
    }
}

private struct AdmissionBudget {
    private var bytes = 0
    private var entries = 0

    mutating func addEntry() throws {
        guard entries < LegacyPreferenceSnapshot.maximumEntries else {
            throw LegacyPreferenceSnapshotError.tooManyEntries
        }
        entries += 1
    }

    mutating func addString(_ value: String) throws {
        let length = value.utf8.count
        guard length <= LegacyPreferenceSnapshot.maximumStringBytes else {
            throw LegacyPreferenceSnapshotError.stringTooLong
        }
        try addBytes(length)
    }

    mutating func addBytes(_ count: Int) throws {
        guard count <= LegacyPreferenceSnapshot.maximumBytes - bytes else {
            throw LegacyPreferenceSnapshotError.tooLarge
        }
        bytes += count
    }
}
