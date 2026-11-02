import CryptoKit
import Foundation

/// Authority to substitute exact generated URL bytes in one immutable body.
/// Publicly constructed prepared documents do not manufacture this authority.
struct ExportResourceSlots: Sendable, Equatable {
    struct Slot: Sendable, Equatable {
        let range: Range<Int>
        let expectedURL: String
        let identity: ExportResourceIdentity
    }

    let bodySHA256: Data
    let occurrences: [Slot]

    static func digest(_ body: String) -> Data {
        Data(SHA256.hash(data: Data(body.utf8)))
    }

    func validate(body: String, manifest: ExportManifest) throws {
        guard Self.digest(body) == bodySHA256 else { throw ExportError.invalidResourceSlots }
        let identities = Set(manifest.resources.map(\.identity))
        let bytes = body.utf8
        var end = 0
        for slot in occurrences {
            try Task.checkCancellation()
            guard slot.range.lowerBound >= end, slot.range.upperBound <= bytes.count,
                  !slot.range.isEmpty, identities.contains(slot.identity) else {
                throw ExportError.invalidResourceSlots
            }
            let start = bytes.index(bytes.startIndex, offsetBy: slot.range.lowerBound)
            let finish = bytes.index(bytes.startIndex, offsetBy: slot.range.upperBound)
            guard bytes[start ..< finish].elementsEqual(slot.expectedURL.utf8) else {
                throw ExportError.invalidResourceSlots
            }
            end = slot.range.upperBound
        }
    }
}

/// Transient, single-render registry. Tokens are unique per emitted occurrence,
/// even when several images share one admitted payload.
final class ExportResourceURLRegistry {
    private let prefix: String
    private let assetsDirectoryName: String
    private let limit: Int
    private let maxOccurrences: Int
    private var identities: [String: ExportResourceIdentity] = [:]

    init(avoiding inputs: [String], assetsDirectoryName: String,
         limit: Int = ExportResourceBudget.standard.maxPreparedHTMLUTF8Bytes,
         maxOccurrences: Int = ExportResourceBudget.maxResourceURLSlots) {
        var candidate: String
        repeat {
            candidate = "MTRESOURCE" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "_"
        } while inputs.contains(where: { $0.contains(candidate) })
        prefix = candidate
        self.assetsDirectoryName = assetsDirectoryName
        self.limit = limit
        self.maxOccurrences = maxOccurrences
    }

    func register(_ identity: ExportResourceIdentity) throws -> String {
        guard identities.count < maxOccurrences else {
            throw ExportError.budgetExceeded(String(localized: "too many image occurrences", bundle: .module))
        }
        let token = prefix + String(identities.count) + "Z"
        identities[token] = identity
        return token
    }

    func resolve(_ html: String) throws -> (html: String, slots: ExportResourceSlots) {
        try Task.checkCancellation()
        guard html.utf8.count <= limit else { throw BoundedExportHTML.tooLarge }
        guard !identities.isEmpty else {
            return (html, ExportResourceSlots(bodySHA256: ExportResourceSlots.digest(html), occurrences: []))
        }
        guard assetsDirectoryName.utf8.count <= limit / 6 else { throw BoundedExportHTML.tooLarge }
        let attributes = try ExportImageURLScanner.sources(in: html)
        var sink = BoundedExportHTML(limit: limit)
        var occurrences: [ExportResourceSlots.Slot] = []
        var seen: Set<String> = []
        let bytes = html.utf8
        var pending = 0
        var written = 0
        for attribute in attributes where attribute.value.hasPrefix(prefix) {
            try Task.checkCancellation()
            guard let identity = identities[attribute.value], seen.insert(attribute.value).inserted else {
                throw ExportError.invalidResourceSlots
            }
            let start = bytes.index(bytes.startIndex, offsetBy: pending)
            let finish = bytes.index(bytes.startIndex, offsetBy: attribute.range.lowerBound)
            guard let lower = String.Index(start, within: html), let upper = String.Index(finish, within: html)
            else { throw ExportError.invalidResourceSlots }
            try sink.append(html[lower ..< upper])
            written += attribute.range.lowerBound - pending
            let url = ExportHTMLWriter.percentEncodedCompanionComponent(assetsDirectoryName) + "/" + identity.fileName
            try sink.append(url)
            occurrences.append(.init(range: written ..< written + url.utf8.count, expectedURL: url, identity: identity))
            written += url.utf8.count
            pending = attribute.range.upperBound
        }
        let tail = bytes.index(bytes.startIndex, offsetBy: pending)
        guard let tailIndex = String.Index(tail, within: html) else { throw ExportError.invalidResourceSlots }
        try sink.append(html[tailIndex...])
        guard seen.count == identities.count,
              !sink.html.contains(prefix) else { throw ExportError.invalidResourceSlots }
        return (
            sink.html,
            ExportResourceSlots(bodySHA256: ExportResourceSlots.digest(sink.html), occurrences: occurrences)
        )
    }
}
