import Foundation

/// Data-only disposition for every supplied key. This deliberately does not
/// load a real preferences domain, resolve fonts, decode URL archives or copy
/// any legacy renderer, file access, update, window or IPC configuration.
public struct LegacyPreferenceReport: Sendable, Equatable {
    public struct FontRequest: Sendable, Equatable {
        public let postScriptName: String
        public let size: Double
    }

    public enum Disposition: Sendable, Equatable {
        case editorBoolean(LegacyImportPlan.Destination, Bool)
        case requiresExactInstalledFont(FontRequest)
        case unconditionalCapability
        case unsupported
        case legacyProvenance
        case calculatedValue
        case ignoredTransient
        case invalid
        case unknown
    }

    public struct Entry: Sendable, Equatable {
        public let key: String
        public let disposition: Disposition
    }

    public let sourceDigest: String
    public let entries: [Entry]

    public init(snapshot: LegacyPreferenceSnapshot) {
        sourceDigest = snapshot.canonicalDigest
        let definitions = Dictionary(uniqueKeysWithValues: LegacyPreferenceCatalog.definitions.map { ($0.key, $0) })
        let conversion = LegacyEditorBooleanConversion(snapshot: snapshot)
        entries = snapshot.values.keys.sorted().compactMap { key in
            guard let value = snapshot.values[key] else { return nil }
            guard let definition = definitions[key] else { return Entry(key: key, disposition: .unknown) }
            return Entry(key: key, disposition: Self.classify(definition, value: value, conversion: conversion))
        }
    }

    private static func classify(
        _ definition: LegacyPreferenceCatalog.Definition,
        value: LegacyPreferenceValue,
        conversion: LegacyEditorBooleanConversion
    ) -> Disposition {
        // IPC and calculated values are never replayed, even if their raw
        // values have the wrong type. Their names do not confer authority.
        if definition.policy == .transient {
            return .ignoredTransient
        }
        if definition.policy == .calculated {
            return .calculatedValue
        }
        guard admits(value, as: definition.valueKind) else { return .invalid }
        return classifyAdmitted(definition, value: value, conversion: conversion)
    }

    private static func classifyAdmitted(
        _ definition: LegacyPreferenceCatalog.Definition,
        value: LegacyPreferenceValue,
        conversion: LegacyEditorBooleanConversion
    ) -> Disposition {
        switch definition.policy {
        case .mapped:
            guard let destination = LegacyEditorBooleanConversion.destination(for: definition.key),
                  let proposed = conversion.proposedValues[destination] else { return .invalid }
            return .editorBoolean(destination, proposed)
        case .font:
            guard let request = fontRequest(value) else { return .invalid }
            return .requiresExactInstalledFont(request)
        case .unconditional:
            return value == .boolean(true) ? .unconditionalCapability : .unsupported
        case .provenance: return .legacyProvenance
        case .unsupported: return .unsupported
        case .calculated: return .calculatedValue
        case .transient: return .ignoredTransient
        }
    }

    private static func admits(_ value: LegacyPreferenceValue, as kind: LegacyPreferenceCatalog.ValueKind) -> Bool {
        switch (kind, value) {
        case (.boolean, .boolean), (.string, .string), (.number, .number): true
        case let (.enumeration, .number(_, spelling)):
            // All three legacy enums have exactly the declared values 0...2.
            if let number = Double(spelling) {
                (0 ... 2).contains(number) && number.rounded() == number
            } else {
                false
            }
        case (.font, .dictionary): fontRequest(value) != nil
        // The directory URL has no destination. Never deserialize a stored
        // archive or turn its string/data representation into a file grant.
        case (.opaque, _): true
        default: false
        }
    }

    private static func fontRequest(_ value: LegacyPreferenceValue) -> FontRequest? {
        guard case let .dictionary(fields) = value,
              Set(fields.keys) == ["name", "size"],
              case let .string(name) = fields["name"], !name.isEmpty, !name.contains("\0"),
              case let .number(_, spelling) = fields["size"],
              let size = Double(spelling), size.isFinite, size > 0,
              size <= FontDescriptor.maximumSupportedSize else { return nil }
        return FontRequest(postScriptName: name, size: size)
    }
}
