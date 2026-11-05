import Foundation

extension ParseEngine {
    static func runOnLargeStack<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: work()) }
            thread.stackSize = parseThreadStackSize
            thread.qualityOfService = .userInitiated
            thread.name = "MarkdownEngine.parse"
            thread.start()
        }
    }

    nonisolated func convertYAMLValue(_ value: Any) -> FrontMatterValue? {
        switch value {
        case let string as String:
            .string(string)
        // Yams 6.2.2 returns native Swift scalars on this platform, so the
        // Bool/Int/Double cases below are the normal path. NSNumber is kept
        // defensively for configurations or future Yams versions that bridge
        // numeric/boolean scalars to Foundation.
        case let bool as Bool:
            .bool(bool)
        case let int as Int:
            .int(int)
        case let double as Double:
            .number(double)
        case let number as NSNumber:
            convertNSNumber(number)
        case let array as [Any]:
            .array(array.compactMap { convertYAMLValue($0) })
        case let dictionary as [String: Any]:
            .dictionary(dictionary.compactMapValues { convertYAMLValue($0) })
        case is NSNull:
            .null
        default:
            nil
        }
    }

    /// Defensive NSNumber→FrontMatterValue bridge. Internal (not private) so
    /// the unsigned-int range guard is testable via `@testable import`.
    nonisolated func convertNSNumber(_ number: NSNumber) -> FrontMatterValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        if CFNumberIsFloatType(number) {
            return .number(number.doubleValue)
        }
        // Yams returns native Swift scalars on this platform, so NSNumber is
        // only a defensive bridge. Use the original scalar encoding so unsigned
        // integers are checked against UInt64 bounds and signed integers against
        // Int64 bounds; fall back to Double when the value does not fit in Int.
        let encoding = String(cString: number.objCType)
        switch encoding {
        case "C", "S", "I", "L", "Q":
            let unsigned = number.uint64Value
            if unsigned <= UInt64(Int.max) {
                return .int(Int(unsigned))
            }
        default:
            let signed = number.int64Value
            if signed >= Int64(Int.min), signed <= Int64(Int.max) {
                return .int(Int(signed))
            }
        }
        return .number(number.doubleValue)
    }
}
