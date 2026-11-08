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

/// A document/revision-bound host for Textual attachment work. Pending or unbound parses keep readable Preview
/// content mounted while denying resource work until its published source matches the current document bytes.
@MainActor
struct SecuredMarkdownResourceHost<Content: View>: View {
    struct Identity: Hashable {
        let tabID: UUID
        let documentID: String
        let recoveryEpoch: UUID
        let fileURL: URL?
        let sourceGeneration: UInt
        let parsedFrame: PreviewResourceParsedFrame?
        let publishedSourceAvailable: Bool
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
    let parsedFrame: PreviewResourceParsedFrame?
    let publishedText: String?
    let content: (PreviewResourceImageLoader, UUID?) -> Content

    @Environment(\.previewResourceWindowState) private var owner
    @State private var slot: Slot?

    private var identity: Identity {
        Identity(
            tabID: tabID, documentID: document.id,
            recoveryEpoch: document.recoveryEpoch, fileURL: document.fileURL,
            sourceGeneration: sourceGeneration,
            parsedFrame: parsedFrame,
            publishedSourceAvailable: publishedText != nil,
            grantRevision: owner?.revision ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )
    }

    private func observedLoader(for current: Slot?) -> PreviewResourceImageLoader {
        #if DEBUG || RELEASE_PREVIEW_PROBE
            PreviewResourceDiagnostics.record(
                "host-body", context: current?.context,
                detail: "generation=\(sourceGeneration) parsedRevision=\(parsedFrame?.revision ?? -1) "
                    + "stored=\(slot?.context?.id.uuidString ?? "none") "
                    + "resourceLoadID=\(current?.loadID.uuidString ?? "none")"
            )
        #endif
        return PreviewResourceImageProvider.loader(for: current?.context)
    }

    var body: some View {
        let currentIdentity = identity
        let current = slot?.identity == currentIdentity ? slot : nil
        // A replacement task may not start before this view disappears. Retire the stored prior context too.
        let retiringContext = slot?.context
        let loader = observedLoader(for: current)
        // BlockView replaces the complete StructuredText attachment cache using resourceLoadID. The outer
        // preview ScrollView and its measured-height state must survive a resource/parse-frame replacement.
        content(loader, current?.loadID)
            .task(id: currentIdentity) {
                guard !Task.isCancelled, identity == currentIdentity else { return }
                // Compare once per immutable identity, never on caret-driven body evaluation. A stale parse
                // must not borrow the current model generation merely because its folder is still allowed.
                let context: PreviewResourceLoad?
                if parsedFrame != nil, let publishedText, publishedText.utf8.elementsEqual(document.text.utf8) {
                    context = owner?.beginPreviewLoad(
                        for: document, tabID: tabID,
                        sourceGeneration: sourceGeneration, grantRevision: currentIdentity.grantRevision,
                        consumer: .markdown
                    )
                } else {
                    if let previous = slot?.context {
                        owner?.retire(.markdown, matching: previous)
                    }
                    context = nil
                }
                guard !Task.isCancelled, identity == currentIdentity else {
                    if let context {
                        owner?.retire(.markdown, matching: context)
                    }
                    return
                }
                // A denied frame also replaces old attachment caches. This identity records application of
                // the frame, not permission; its loader has no provider when the context is absent.
                let next = Slot(identity: currentIdentity, loadID: UUID(), context: context)
                #if DEBUG || RELEASE_PREVIEW_PROBE
                    PreviewResourceDiagnostics.record(
                        "slot-installed", context: context,
                        detail: "generation=\(sourceGeneration) parsedRevision=\(parsedFrame?.revision ?? -1) "
                            + "resourceLoadID=\(next.loadID.uuidString)"
                    )
                #endif
                slot = next
            }
            .onDisappear {
                if let context = retiringContext {
                    owner?.retire(.markdown, matching: context)
                }
            }
    }
}
