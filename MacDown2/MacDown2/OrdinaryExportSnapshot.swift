import ExportService
import FileCore
import Foundation
import MarkdownEngine
import Themes

/// Immutable source and presentation inputs captured after the ordinary
/// export panel is accepted, before parsing or rendering can suspend.
struct OrdinaryExportSnapshot: Sendable, Equatable {
    let documentID: String
    let recoveryEpoch: UUID
    let text: String
    let sourceGeneration: UInt
    let theme: Theme
    let documentURL: URL?
    let resourceAccess: ExportResourceAccess?
    let protectedSourceIdentity: ExportProtectedFileIdentity?
    let parseOptions: MarkdownParseOptions

    init(
        document: FileCore.FileDocument,
        theme: Theme,
        parseOptions: MarkdownParseOptions,
        openResourceAccess: @escaping @Sendable (URL) -> ExportResourceAccess? = {
            try? ExportResourceAccess(openingDirectory: $0)
        }
    ) async {
        // A granted directory may be on a slow or disconnected volume. Keep
        // its realpath/open work off the window's main actor after the source
        // value has been captured from the accepted document.
        let access = await Self.resourceAccess(for: document.fileURL, using: openResourceAccess)
        documentID = document.id
        recoveryEpoch = document.recoveryEpoch
        text = document.text
        sourceGeneration = document.mutationGeneration
        self.theme = theme
        documentURL = document.fileURL
        protectedSourceIdentity = ExportProtectedFileIdentity(document: document)
        resourceAccess = access
        self.parseOptions = parseOptions
    }

    @concurrent
    private nonisolated static func resourceAccess(
        for documentURL: URL?,
        using open: @Sendable (URL) -> ExportResourceAccess?
    ) async -> ExportResourceAccess? {
        guard let documentURL else { return nil }
        return open(documentURL.deletingLastPathComponent())
    }

    func request(
        contributions: [ExportDerivedContribution], headingPreparation: HeadingAnchorPreparation? = nil
    ) -> ExportRequest {
        ExportRequest(
            text: text,
            sourceGeneration: sourceGeneration,
            theme: theme,
            documentURL: documentURL,
            resourceAccess: resourceAccess,
            protectedSourceIdentity: protectedSourceIdentity,
            parseOptions: parseOptions,
            contributions: contributions,
            headingPreparation: headingPreparation
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
