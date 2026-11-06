import FileCore
import MarkdownEngine
import Preview
import SwiftUI

/// The displayed parse may change without another model edit (for example, a delayed parse or option reparse).
/// Its identity is separate from the model generation captured by the view.
struct PreviewResourceParsedFrame: Hashable {
    let parserIdentity: UUID
    let revision: Int
    let sourceSHA256: String

    init?(parserIdentity: UUID, document: MarkdownDocument) {
        guard let sourceSHA256 = document.sourceSHA256 else { return nil }
        self.parserIdentity = parserIdentity
        revision = document.revision
        self.sourceSHA256 = sourceSHA256
    }
}

/// A document/revision-bound host for Textual attachment work. The existing preview does not use this host until
/// HTML and Markdown both enforce the grant contract; tests can exercise it without changing the current renderer.
@MainActor
struct SecuredMarkdownResourceHost<Content: View>: View {
    struct Identity: Hashable {
        let tabID: UUID
        let documentID: String
        let recoveryEpoch: UUID
        let fileURL: URL?
        let sourceGeneration: UInt
        let parsedFrame: PreviewResourceParsedFrame
        let grantRevision: UUID
    }

    private struct Slot {
        let identity: Identity
        let loadID: UUID
        let context: PreviewResourceLoad?
    }

    let tabID: UUID
    let document: FileCore.FileDocument
    let sourceGeneration: UInt
    let parsedFrame: PreviewResourceParsedFrame
    let content: (PreviewResourceImageLoader, UUID?) -> Content

    @Environment(\.previewResourceWindowState) private var owner
    @State private var slot: Slot?

    private var identity: Identity {
        Identity(
            tabID: tabID, documentID: document.id,
            recoveryEpoch: document.recoveryEpoch, fileURL: document.fileURL,
            sourceGeneration: sourceGeneration,
            parsedFrame: parsedFrame,
            grantRevision: owner?.revision ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )
    }

    var body: some View {
        let currentIdentity = identity
        let current = slot?.identity == currentIdentity ? slot : nil
        let loader = PreviewResourceImageProvider.loader(for: current?.context)
        // BlockView replaces the complete StructuredText attachment cache using resourceLoadID. The outer
        // preview ScrollView and its measured-height state must survive a resource/parse-frame replacement.
        content(loader, current?.loadID)
            .task(id: currentIdentity) {
                guard !Task.isCancelled, identity == currentIdentity else { return }
                let context = owner?.beginPreviewLoad(
                    for: document, tabID: tabID,
                    sourceGeneration: sourceGeneration, grantRevision: currentIdentity.grantRevision,
                    consumer: .markdown
                )
                guard !Task.isCancelled, identity == currentIdentity else {
                    if let context {
                        owner?.retire(.markdown, matching: context)
                    }
                    return
                }
                slot = Slot(identity: currentIdentity, loadID: UUID(), context: context)
            }
            .onDisappear {
                if let context = current?.context {
                    owner?.retire(.markdown, matching: context)
                }
            }
    }
}
