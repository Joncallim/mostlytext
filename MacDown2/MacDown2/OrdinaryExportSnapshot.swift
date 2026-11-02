import ExportService
import FileCore
import Foundation
import MarkdownEngine
import Themes

/// Immutable source and presentation inputs captured after the ordinary
/// export panel is accepted, before parsing or rendering can suspend.
struct OrdinaryExportSnapshot: Sendable, Equatable {
    let text: String
    let sourceGeneration: UInt
    let theme: Theme
    let documentURL: URL?
    let resourceAccess: ExportResourceAccess?
    let protectedSourceIdentity: ExportProtectedFileIdentity?
    let parseOptions: MarkdownParseOptions

    init(document: FileCore.FileDocument, theme: Theme, parseOptions: MarkdownParseOptions) {
        text = document.text
        sourceGeneration = document.mutationGeneration
        self.theme = theme
        documentURL = document.fileURL
        protectedSourceIdentity = ExportProtectedFileIdentity(document: document)
        resourceAccess = document.fileURL.flatMap {
            try? ExportResourceAccess(openingDirectory: $0.deletingLastPathComponent())
        }
        self.parseOptions = parseOptions
    }

    func request(contributions: [ExportDerivedContribution]) -> ExportRequest {
        ExportRequest(
            text: text,
            sourceGeneration: sourceGeneration,
            theme: theme,
            documentURL: documentURL,
            resourceAccess: resourceAccess,
            protectedSourceIdentity: protectedSourceIdentity,
            parseOptions: parseOptions,
            contributions: contributions
        )
    }
}

extension ExportProtectedFileIdentity {
    init?(document: FileCore.FileDocument) {
        guard let identity = document.lastKnownRevision?.fileObjectID,
              let inode = UInt64(identity.file),
              let device = UInt64(identity.volume) ?? Int64(identity.volume).map({ UInt64(truncatingIfNeeded: $0) })
        else { return nil }
        self.init(device: device, inode: inode)
    }
}
