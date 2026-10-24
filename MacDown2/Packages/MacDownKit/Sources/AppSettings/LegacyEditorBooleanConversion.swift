import Foundation

/// Source-key proposals for three original-MacDown editor controls whose
/// Boolean behavior has a direct current editor setting. This does not decide
/// destination precedence or write a preference. Every other legacy key stays
/// with the complete #53 disposition plan.
public struct LegacyEditorBooleanConversion: Sendable, Equatable {
    public enum Destination: String, Sendable, Hashable {
        case autoIncrementOrderedLists
        case convertsTabsToSpaces
        case smartHome
    }

    public let proposedValues: [Destination: Bool]
    public let invalidSourceKeys: [String]

    public init(snapshot: LegacyPreferenceSnapshot) {
        let mappings: [(String, Destination)] = [
            ("editorAutoIncrementNumberedLists", .autoIncrementOrderedLists),
            ("editorConvertTabs", .convertsTabsToSpaces),
            ("editorSmartHome", .smartHome),
        ]
        var proposed: [Destination: Bool] = [:]
        var invalid: [String] = []
        for (key, destination) in mappings {
            guard let value = snapshot.values[key] else { continue }
            if case let .boolean(boolean) = value {
                proposed[destination] = boolean
            } else {
                invalid.append(key)
            }
        }
        proposedValues = proposed
        invalidSourceKeys = invalid
    }
}
