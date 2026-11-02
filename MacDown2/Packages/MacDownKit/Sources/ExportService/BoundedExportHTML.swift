import Foundation

/// Counts UTF-8 bytes before allocating each piece of the final document.
/// This bounds accepted HTML, not process peak memory or WebKit's layout cost.
struct BoundedExportHTML {
    let limit: Int
    let measuring: Bool
    private(set) var html = ""
    private var count = 0

    init(limit: Int, measuring: Bool = false) {
        self.limit = limit
        self.measuring = measuring
    }

    static var tooLarge: ExportError {
        .budgetExceeded(String(localized: "final HTML exceeds the export safety limit", bundle: .module))
    }

    func requireCapacity(_ bytes: Int) throws {
        try Task.checkCancellation()
        guard bytes >= 0, limit >= 0, count <= limit, bytes <= limit - count else { throw Self.tooLarge }
    }

    func requireScratchCapacity(_ bytes: Int) throws {
        try BoundedExportHTML(limit: limit).requireCapacity(bytes)
    }

    mutating func append(_ text: some StringProtocol) throws {
        let bytes = text.utf8.count
        try requireCapacity(bytes)
        if !measuring {
            html.append(contentsOf: text)
        }
        count += bytes // requireCapacity proves this cannot overflow.
    }

    mutating func appendCount(_ bytes: Int) throws {
        try requireCapacity(bytes)
        count += bytes
    }

    mutating func appendEscaped(_ text: String) throws {
        try requireCapacity(text.utf8.count)
        var pending = text.startIndex
        var scanned = 0
        for index in text.unicodeScalars.indices {
            if scanned.isMultiple(of: 4096) {
                try Task.checkCancellation()
            }
            scanned += 1
            let replacement: String
            switch text.unicodeScalars[index] {
            case "&": replacement = "&amp;"
            case "<": replacement = "&lt;"
            case ">": replacement = "&gt;"
            case "\"": replacement = "&quot;"
            case "'": replacement = "&#39;"
            default: continue
            }
            try append(text[pending ..< index])
            try append(replacement)
            pending = text.unicodeScalars.index(after: index)
        }
        try append(text[pending...])
    }

    static func dataURISize(payloadBytes: Int, mimeBytes: Int) throws -> Int {
        guard payloadBytes >= 0, mimeBytes >= 0 else { throw tooLarge }
        let (rounded, overflow1) = payloadBytes.addingReportingOverflow(2)
        let (base64, overflow2) = (rounded / 3).multipliedReportingOverflow(by: 4)
        let (header, overflow3) = mimeBytes.addingReportingOverflow(13) // data: + ;base64,
        let (total, overflow4) = base64.addingReportingOverflow(header)
        guard !overflow1, !overflow2, !overflow3, !overflow4 else { throw tooLarge }
        return total
    }
}

extension BuiltInExportTemplate {
    struct BoundedMetadata {
        let title: String
        let visibleTitle: String?
        let headExtras: String
    }

    /// Same bytes as document(), assembled incrementally under one final cap.
    static func boundedDocument(
        metadata: BoundedMetadata, limit: Int,
        style: (inout BoundedExportHTML) throws -> Void,
        body: (inout BoundedExportHTML) throws -> Void
    ) throws -> String {
        // Preflight the entire shell and body without materializing output.
        _ = try assemble(metadata: metadata,
                         limit: limit, measuring: true, style: style, body: body)
        return try assemble(metadata: metadata,
                            limit: limit, measuring: false, style: style, body: body)
    }

    private static func assemble(
        metadata: BoundedMetadata, limit: Int, measuring: Bool,
        style: (inout BoundedExportHTML) throws -> Void,
        body: (inout BoundedExportHTML) throws -> Void
    ) throws -> String {
        let (title, visibleTitle, headExtras) = (metadata.title, metadata.visibleTitle, metadata.headExtras)
        var sink = BoundedExportHTML(limit: limit, measuring: measuring)
        try sink.append("<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n")
        if !headExtras.isEmpty {
            try sink.append(headExtras)
            try sink.append("\n")
        }
        try sink
            .append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, user-scalable=yes\">\n")
        if !title.isEmpty {
            try sink.append("<title>")
            try sink.appendEscaped(title)
            try sink.append("</title>\n")
        }
        try style(&sink)
        try sink.append("\n</head>\n<body>\n")
        if let visibleTitle {
            try sink.append("<h1>")
            try sink.appendEscaped(visibleTitle)
            try sink.append("</h1>\n")
        }
        try body(&sink)
        try sink.append("\n</body>\n</html>")
        return sink.html
    }
}
