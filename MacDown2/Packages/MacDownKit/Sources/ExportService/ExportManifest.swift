import Foundation

/// One exact authored URL spelling and the companion it actually resolved to.
public struct ExportResourceReferenceMapping: Sendable, Equatable {
    public let authoredReference: String
    public let companionFileName: String

    public init(authoredReference: String, companionFileName: String) {
        self.authoredReference = authoredReference
        self.companionFileName = companionFileName
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.authoredReference.utf8.elementsEqual(rhs.authoredReference.utf8)
            && lhs.companionFileName == rhs.companionFileName
    }
}

/// The immutable set of resources an export must carry.
///
/// Built by a transient manifest builder that deduplicates by resource identity
/// and then freezes once; there is exactly one resource truth per export.
public struct ExportManifest: Sendable, Equatable {
    /// Resources in a stable, deterministic order (by identity) so identical
    /// inputs produce byte-identical companion directories.
    public let resources: [ExportResource]

    /// Maps an authored reference (the original URL string from a Markdown
    /// link/image) to the content-addressed companion filename it resolved to.
    ///
    /// This is a record of what happened, not the mechanism: references are
    /// rewritten in the cmark tree during composition, so nothing rewrites the
    /// rendered HTML afterwards. Callers use it to report or audit the mapping.
    /// Compatibility view: Swift Dictionary merges canonically equivalent
    /// String keys. Use referenceMappings for a complete byte-exact audit.
    public let referenceMap: [String: String]
    public let referenceMappings: [ExportResourceReferenceMapping]

    public init(resources: [ExportResource], referenceMap: [String: String]) {
        self.resources = resources
        self.referenceMap = referenceMap
        referenceMappings = referenceMap.map {
            ExportResourceReferenceMapping(authoredReference: $0.key, companionFileName: $0.value)
        }.sorted { $0.authoredReference.utf8.lexicographicallyPrecedes($1.authoredReference.utf8) }
    }

    public init(resources: [ExportResource], referenceMappings: [ExportResourceReferenceMapping]) {
        self.resources = resources
        self.referenceMappings = referenceMappings.sorted {
            $0.authoredReference.utf8.lexicographicallyPrecedes($1.authoredReference.utf8)
        }
        referenceMap = self.referenceMappings.reduce(into: [:]) { result, entry in
            if result[entry.authoredReference] == nil {
                result[entry.authoredReference] = entry.companionFileName
            }
        }
    }

    public static let empty = ExportManifest(resources: [], referenceMap: [:])
}
