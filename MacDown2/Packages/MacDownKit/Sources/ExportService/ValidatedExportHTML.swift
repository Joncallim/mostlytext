import CryptoKit
import Foundation

/// A final, marker-free HTML byte string accepted for one frozen source and
/// destination. Only ExportService can construct it; callers cannot turn an
/// arbitrary PreparedExportDocument into a publication receipt.
public struct ValidatedExportHTML: Sendable {
    /// Owned UTF-8 bytes consumed unchanged by the file or PDF WebKit writer.
    public let utf8: Data
    public let sourceGeneration: UInt

    let target: ExportTarget
    let sourceSHA256: String
    let bytesSHA256: String
    let resources: [ExportResource]
    let assetsDirectoryName: String
    let diagnostics: [ExportDiagnostic]
    let companionReferencesKnown: Bool

    init(publication: SVGAssemblyOwnership.Publication, prepared: PreparedExportDocument,
         target: ExportTarget, sourceText: String, diagnostics: [ExportDiagnostic]? = nil) {
        utf8 = Data(publication.html.utf8)
        sourceGeneration = prepared.sourceGeneration
        self.target = target
        sourceSHA256 = Self.sha256(Data(sourceText.utf8))
        bytesSHA256 = Self.sha256(utf8)
        resources = prepared.manifest.resources
        assetsDirectoryName = prepared.assetsDirectoryName
        self.diagnostics = diagnostics ?? prepared.diagnostics
        companionReferencesKnown = prepared.hasClosedCompanionReferences(for: sourceText)
    }

    func matches(target: ExportTarget, sourceText: String, generation: UInt) -> Bool {
        self.target == target && sourceGeneration == generation
            && sourceSHA256 == Self.sha256(Data(sourceText.utf8))
            && bytesSHA256 == Self.sha256(utf8)
    }

    func bytesAreIntact() -> Bool {
        bytesSHA256 == Self.sha256(utf8)
    }

    public func isForPDF(at url: URL) -> Bool {
        target == .pdf(url: url) && bytesAreIntact()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
