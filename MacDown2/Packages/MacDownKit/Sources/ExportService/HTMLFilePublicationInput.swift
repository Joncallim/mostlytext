import Foundation

/// Already assembled immutable bytes; no document parsing or UI work under the
/// destination publication lock.
struct HTMLFilePublicationInput: Sendable {
    let url: URL
    let mode: HTMLExportMode
    let bytes: Data
    let resources: [ExportResource]
    let assetsDirectoryName: String
    let diagnostics: [ExportDiagnostic]
    let referencesKnown: Bool

    init(url: URL, mode: HTMLExportMode, bytes: Data, resources: [ExportResource],
         assetsDirectoryName: String, diagnostics: [ExportDiagnostic], referencesKnown: Bool = false) {
        self.url = url
        self.mode = mode
        self.bytes = bytes
        self.resources = resources
        self.assetsDirectoryName = assetsDirectoryName
        self.diagnostics = diagnostics
        self.referencesKnown = referencesKnown
    }
}

/// Ownership is primary-bound, not merely a filename pattern or a legacy
/// marker. Exact bytes intentionally reject ambiguous names and old versions.
enum ExportAssetOwnerMarker {
    private struct Record: Encodable {
        let schema = 2
        let producer = "MostlyText Export"
        let primary: String
        let assets: String
    }

    static func bytes(primary: String, assets: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Record(primary: primary, assets: assets))
    }
}
