@testable import ExportService
import Foundation

/// Synthetic emitter for fixtures whose img/src values are deliberately
/// generated resource URLs. Never used by production to infer authority.
enum ExportSlotTestSupport {
    static func registeringGeneratedImages(_ input: PreparedExportDocument) throws -> PreparedExportDocument {
        let registry = ExportResourceURLRegistry(
            avoiding: [input.bodyHTML],
            assetsDirectoryName: input.assetsDirectoryName
        )
        var identities: [String: ExportResourceIdentity] = [:]
        for resource in input.manifest.resources {
            for directory in ExportHTMLWriter.referenceForms(of: input.assetsDirectoryName) {
                identities[directory + "/" + resource.identity.fileName] = resource.identity
            }
        }
        let bytes = Array(input.bodyHTML.utf8)
        var marked = ""
        var pending = 0
        for attribute in try ExportImageURLScanner.sources(in: input.bodyHTML) {
            guard let identity = identities[attribute.value] else { continue }
            guard let chunk = String(bytes: bytes[pending ..< attribute.range.lowerBound], encoding: .utf8)
            else { throw ExportError.invalidResourceSlots }
            marked += chunk
            marked += try registry.register(identity)
            pending = attribute.range.upperBound
        }
        guard let tail = String(bytes: bytes[pending...], encoding: .utf8)
        else { throw ExportError.invalidResourceSlots }
        marked += tail
        let output = try registry.resolve(marked)
        return PreparedExportDocument(
            title: input.title, visibleTitle: input.visibleTitle, bodyHTML: output.html,
            assetsDirectoryName: input.assetsDirectoryName, stylesheet: input.stylesheet,
            manifest: input.manifest, diagnostics: input.diagnostics, sourceGeneration: input.sourceGeneration,
            preservesRawHTML: input.preservesRawHTML
        ).registeringResourceSlots(output.slots)
    }
}
