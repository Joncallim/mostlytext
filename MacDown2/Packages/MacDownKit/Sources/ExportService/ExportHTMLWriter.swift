import Foundation

/// Renders a `PreparedExportDocument` into a complete HTML document.
///
/// Two output shapes exist:
/// - **Self-contained** — CSS and every resource are embedded in one file
///   (data URIs). Used for the `.selfContained` target and as the PDF input.
/// - **Companion** — resources are referenced as `<name>.assets/<file>` (written
///   separately), and CSS is either embedded or linked.
public enum ExportHTMLWriter {
    /// The companion directory name used when no primary URL is available to
    /// derive one from (a `PreparedExportDocument` built directly by a test, or
    /// any future caller that composes without a destination in hand).
    public static let defaultAssetsDirectoryName = "report.assets"

    /// The per-document companion directory name: the primary file's own
    /// basename.
    ///
    /// Two documents exported into the same folder must never share a
    /// companion directory — sharing one means exporting the second can
    /// overwrite the first's linked stylesheet or leave its resources exposed
    /// to the other's cleanup. Naming the directory after the document it
    /// belongs to makes every export's companions exclusively its own.
    public static func assetsDirectoryName(for primaryURL: URL) -> String {
        let stem = primaryURL.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? defaultAssetsDirectoryName : "\(stem).assets"
    }

    /// The content-addressed resource for the combined stylesheet, used for the
    /// `.linked` CSS delivery.
    ///
    /// Computed fresh from the stylesheet text rather than cached on
    /// `PreparedExportDocument`, so the HTML body's `<link>` reference and the
    /// bytes `ExportFileWriter` writes to disk are always computed the same
    /// way and can never name two different files.
    static func linkedStylesheetResource(for stylesheet: String) -> ExportResource {
        let bytes = Data(stylesheet.utf8)
        return ExportResource(identity: ExportResourceIdentity(bytes: bytes, mimeType: "text/css"), bytes: bytes)
    }

    /// A complete self-contained HTML document: embedded stylesheet and
    /// resources as data URIs.
    ///
    /// `additionalHead` is emitted immediately after `<head>`, ahead of the
    /// title and stylesheet, so a caller can install a document-wide policy
    /// (the PDF adapter's Content-Security-Policy) without rewriting the
    /// rendered markup afterwards.
    public static func selfContainedHTML(
        from prepared: PreparedExportDocument,
        additionalHead: String = ""
    ) throws -> String {
        try selfContainedHTML(from: prepared, additionalHead: additionalHead,
                              limit: ExportResourceBudget.maxFinalHTMLUTF8Bytes)
    }

    static func selfContainedHTML(
        from prepared: PreparedExportDocument, additionalHead: String = "", limit: Int
    ) throws -> String {
        try document(from: prepared, style: .embedded, additionalHead: additionalHead, limit: limit) { sink in
            try embedResources(in: prepared.bodyHTML, manifest: prepared.manifest,
                               assetsDirectoryName: prepared.assetsDirectoryName, into: &sink)
        }
    }

    static func selfContainedBody(from prepared: PreparedExportDocument) throws -> String {
        var sink = BoundedExportHTML(limit: ExportResourceBudget.maxFinalHTMLUTF8Bytes)
        try embedResources(in: prepared.bodyHTML, manifest: prepared.manifest,
                           assetsDirectoryName: prepared.assetsDirectoryName, into: &sink)
        return sink.html
    }

    /// A complete companion document. Oversized output throws before publishing.
    public static func companionHTML(
        from prepared: PreparedExportDocument, style: ExportStyleEmbedding,
        additionalHead: String = ""
    ) throws -> String {
        try companionHTML(from: prepared, style: style, additionalHead: additionalHead,
                          limit: ExportResourceBudget.maxFinalHTMLUTF8Bytes)
    }

    static func companionHTML(
        from prepared: PreparedExportDocument, style: ExportStyleEmbedding,
        additionalHead: String = "", limit: Int
    ) throws -> String {
        try document(from: prepared, style: style, additionalHead: additionalHead, limit: limit) { sink in
            try sink.append(prepared.bodyHTML)
        }
    }

    private static func document(
        from prepared: PreparedExportDocument, style: ExportStyleEmbedding,
        additionalHead: String, limit: Int, body: (inout BoundedExportHTML) throws -> Void
    ) throws -> String {
        try BuiltInExportTemplate.boundedDocument(
            metadata: .init(title: prepared.title, visibleTitle: prepared.visibleTitle, headExtras: additionalHead),
            limit: limit, style: { sink in
                switch style {
                case .embedded:
                    try sink.append("<style>\n")
                    try sink.append(prepared.stylesheet)
                    try sink.append("\n</style>")
                case .linked:
                    // Check inputs before allocating the CSS Data or URL encodings.
                    guard prepared.stylesheet.utf8.count <= ExportResourceBudget.maxFinalHTMLUTF8Bytes
                    else { throw BoundedExportHTML.tooLarge }
                    try sink.requireScratchCapacity(Self.encodedComponentUpperBound(prepared.assetsDirectoryName))
                    let resource = linkedStylesheetResource(for: prepared.stylesheet)
                    try sink.append("<link rel=\"stylesheet\" href=\"")
                    try sink.append(percentEncodedCompanionComponent(prepared.assetsDirectoryName))
                    try sink.append("/" + resource.identity.fileName + "\">")
                }
            }, body: body
        )
    }

    /// 64 hex digits, a dot, and room for any canonical extension.
    private static let maxCompanionNameLength = 96

    /// One scan of the original body, charging every replacement occurrence.
    /// Textual matching is retained here; registered URL slots remain separate
    /// work and authored text that resembles a companion path can still match.
    private static func embedResources(
        in body: String, manifest: ExportManifest, assetsDirectoryName: String,
        into sink: inout BoundedExportHTML
    ) throws {
        try Task.checkCancellation()
        guard !manifest.resources.isEmpty else { try sink.append(body); return }
        try sink.requireScratchCapacity(encodedComponentUpperBound(assetsDirectoryName))
        let prefixes = referenceForms(of: assetsDirectoryName).map { $0 + "/" }
        var resources: [String: ExportResource] = [:]
        for resource in manifest.resources {
            try Task.checkCancellation()
            try sink.requireScratchCapacity(resource.identity.sha256.utf8.count)
            try sink.requireScratchCapacity(resource.identity.mimeType.utf8.count)
            resources[resource.identity.fileName] = resource
        }
        var dataURIs: [String: String] = [:]
        var pending = body.startIndex
        var hits = prefixes.map { body.range(of: $0) }
        while true {
            try Task.checkCancellation()
            guard let hit = hits.compactMap(\.self).min(by: { $0.lowerBound < $1.lowerBound }) else { break }
            var searchStart = hit.upperBound
            // Cache each prefix's next match, including misses. Re-searching
            // absent forms after every hit would make repeated paths quadratic.
            defer {
                for index in hits.indices {
                    if let previous = hits[index], previous.lowerBound < searchStart {
                        hits[index] = body.range(of: prefixes[index], range: searchStart ..< body.endIndex)
                    }
                }
            }
            let candidate = body[hit.upperBound...].prefix(maxCompanionNameLength)
                .prefix { $0.isLetter || $0.isNumber || $0 == "." }
            let name = String(candidate)
            guard let resource = resources[name] else { searchStart = hit.upperBound; continue }
            try sink.append(body[pending ..< hit.lowerBound])
            try appendResource(resource, named: name, cache: &dataURIs, into: &sink)
            pending = candidate.endIndex
            searchStart = candidate.endIndex
        }
        try sink.append(body[pending...])
    }

    private static func appendResource(
        _ resource: ExportResource, named name: String,
        cache: inout [String: String], into sink: inout BoundedExportHTML
    ) throws {
        if let uri = cache[name] {
            try sink.append(uri); return
        }
        // Reject before base64 expansion, including synthetic Int.max sizes.
        let size = try BoundedExportHTML.dataURISize(
            payloadBytes: resource.bytes.count, mimeBytes: resource.identity.mimeType.utf8.count
        )
        try sink.requireCapacity(size)
        if sink.measuring {
            try sink.appendCount(size); return
        }
        let uri = "data:\(resource.identity.mimeType);base64,\(resource.bytes.base64EncodedString())"
        try sink.append(uri)
        cache[name] = uri
    }

    private static func encodedComponentUpperBound(_ name: String) throws -> Int {
        let (size, overflow) = name.utf8.count.multipliedReportingOverflow(by: 6)
        guard !overflow else { throw BoundedExportHTML.tooLarge }
        return size
    }

    /// The raw directory name plus the form cmark writes into an `href`/`src`.
    static func referenceForms(of directoryName: String) -> [String] {
        var forms: [String] = []
        let candidates = [
            percentEncodedCompanionComponent(directoryName),
            directoryName,
            cmarkEscapedDestination(directoryName),
        ]
        for form in candidates where !forms.contains(form) {
            forms.append(form)
        }
        return forms
    }

    /// An assets directory is one filesystem path component, not a complete
    /// URL. Encode even cmark-safe `#`, `?` and `%` so the browser cannot treat
    /// its name as a fragment, query, or pre-existing percent escape.
    static func percentEncodedCompanionComponent(_ name: String) -> String {
        let safe = Set(Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".utf8))
        var result = ""
        for byte in name.utf8 {
            result += safe.contains(byte) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
        }
        return result
    }

    /// cmark's `houdini_escape_href`: unreserved/safe ASCII stays, `&` and `'`
    /// become entities, every other UTF-8 byte is `%XX`.
    static func cmarkEscapedDestination(_ text: String) -> String {
        let safe = Set(Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.+!*(),%#@?=;:/$~".utf8))
        var output = ""
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "&"): output += "&amp;"
            case UInt8(ascii: "'"): output += "&#x27;"
            case let byte where safe.contains(byte): output += String(UnicodeScalar(byte))
            default: output += String(format: "%%%02X", byte)
            }
        }
        return output
    }
}
