import AppKit
import Diagrams
import DiagramsD2
import DiagramsGraphviz
import SwiftUI
import Textual
import Themes

/// Split out from `TextualMarkdownPreview.swift` purely to stay under
/// SwiftLint's `file_length` limit, matching this package's own
/// `DocumentEditorSplitView+Mermaid.swift` precedent (app target) for
/// splitting a large view's supporting code into its own file.
struct BlockView: View {
    let block: PreviewBlock
    let theme: PreviewTheme
    let linkResolver: PreviewLinkResolver
    let resourceImageLoader: PreviewResourceImageLoader?
    let resourceLoadID: UUID?
    @Environment(\.previewOpenDocument) private var openDocument
    let mathContent: PreviewMathContent?
    let onMathSourceAction: (@MainActor @Sendable (UUID, UUID) -> Void)?
    let mermaidFenceView: ((String) -> AnyView)?
    let d2FenceView: ((String) -> AnyView)?
    let graphvizFenceView: ((String) -> AnyView)?

    private var isLiteral: Bool {
        Self.showsLiteralSource(block: block, mathContent: mathContent)
    }

    static func showsLiteralSource(block: PreviewBlock, mathContent: PreviewMathContent?) -> Bool {
        if case .literal? = mathContent?.blocks[block.id] {
            return true
        }
        if case .codeBlock = block.kind {
            return false
        }
        let pending = mathContent == nil || (mathContent?.isPending == true && block.sourceAnchor != nil)
        return pending && block.source.utf8.contains(36)
    }

    private var preparedInput: PreviewMathInput? {
        if case let .parsed(input)? = mathContent?.blocks[block.id] {
            return input
        }
        return nil
    }

    private var usesSourceGuard: Bool {
        preparedInput != nil || (mathContent?.isPending == true && block.sourceAnchor != nil)
    }

    private var contentIdentity: PreviewBlockContentIdentity {
        .init(source: block.source, baseURL: linkResolver.baseURL, input: preparedInput,
              frameID: mathContent?.id, guarded: usesSourceGuard)
    }

    private var parser: any MarkupParser {
        if let input = preparedInput {
            return PreviewMathMarkupParser(input: input, attachments: mathContent?.attachments ?? [:],
                                           baseURL: linkResolver.baseURL)
        }
        if usesSourceGuard {
            return PreviewPendingMarkupParser(baseURL: linkResolver.baseURL)
        }
        // Pending, unknown and generated blocks cannot run another dollar pass.
        return PreviewMarkupParser(baseURL: linkResolver.baseURL, syntaxExtensions: [])
    }

    /// `block.source` for a `.codeBlock` includes both fence delimiter
    /// lines (confirmed against `PreviewBlock.blocks(from:text:)`'s own
    /// slicing) — stripped here via the same helper `MermaidFenceScanner`
    /// uses for Export, so both paths recover identical diagram source from
    /// differently-produced but identically-sliced text.
    private var mermaidFenceSource: String? {
        guard case let .codeBlock(language) = block.kind,
              let language, language.caseInsensitiveCompare("mermaid") == .orderedSame
        else { return nil }
        return MermaidFenceContent.stripDelimiters(from: block.source)
    }

    private var d2FenceSource: String? {
        guard case let .codeBlock(language) = block.kind,
              let language, language.caseInsensitiveCompare("d2") == .orderedSame
        else { return nil }
        return D2FenceContent.stripDelimiters(from: block.source)
    }

    private static let graphvizLanguages: Set<String> = ["dot", "graphviz"]

    private var graphvizFenceSource: String? {
        guard case let .codeBlock(language) = block.kind,
              let language, Self.graphvizLanguages.contains(language.lowercased())
        else { return nil }
        return GraphvizFenceContent.stripDelimiters(from: block.source)
    }

    var body: some View {
        Group {
            if block.isOversize || isLiteral {
                // Oversize blocks skip Textual entirely: it has no size limit
                // of its own and is documented to freeze/crash on inputs
                // around 100 KB (see ``PreviewBlock/oversizeByteThreshold``).
                OversizeTextView(source: block.source)
            } else if let mermaidFenceSource, let mermaidFenceView {
                mermaidFenceView(mermaidFenceSource)
            } else if let d2FenceSource, let d2FenceView {
                d2FenceView(d2FenceSource)
            } else if let graphvizFenceSource, let graphvizFenceView {
                graphvizFenceView(graphvizFenceSource)
            } else {
                // `baseURL` resolves relative image sources (e.g.
                // `![plot](images/plot.png)`) during parsing. `linkResolver`
                // carries the same document base URL used to resolve clicked
                // links, so both paths agree on what "relative" means.
                secureOrLegacyText
                    .tint(theme.linkColor.swiftUIColor)
                    .environment(
                        \.openURL,
                        OpenURLAction { url in
                            let resolved = linkResolver.resolve(url)
                            switch PreviewLinkResolver.action(for: resolved, currentDocument: linkResolver.baseURL) {
                            case .open: NSWorkspace.shared.open(resolved)
                            case let .openInApp(document):
                                // Through MostlyText when the host provides it; otherwise the
                                // default handler for a text document.
                                if let openDocument {
                                    openDocument(document)
                                } else {
                                    NSWorkspace.shared.open(document)
                                }
                            case .reveal: NSWorkspace.shared.activateFileViewerSelecting([resolved])
                            case .ignore: break
                            }
                            return .handled
                        }
                    )
            }
        }
        .foregroundStyle(theme.foreground.swiftUIColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var secureOrLegacyText: some View {
        let frameID = mathContent?.id
        let action = onMathSourceAction
        // Analysis arrival changes parser/attachment identity even if the
        // authored text is unchanged. The outer scroll-sync block stays stable.
        let content = StructuredText(block.source, parser: parser)
            .id(contentIdentity)
            .textual.attachmentAccessibilityAction { occurrenceID in
                guard let frameID else { return }
                action?(frameID, occurrenceID)
            }
        if let resourceImageLoader {
            // Textual keys its attachment task only by attributed text and can publish after cancellation.
            // A new resource identity must therefore replace its complete state subtree.
            content.id(resourceLoadID)
                .textual.imageAttachmentLoader(resourceImageLoader)
                .textual.emojiAttachmentLoader(resourceImageLoader)
                .textual.textSelection(.enabled)
        } else {
            content
        }
    }

    static func inlineMathContentID(blockSource: String, renderedSource: String) -> String {
        blockSource.contains("$") ? renderedSource : ""
    }
}

private struct OversizeTextView: View {
    let source: String
    @State private var chunks: [String]

    init(source: String) {
        self.source = source
        _chunks = State(initialValue: OversizeTextChunker.displayChunks(source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                Text(chunk)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .onChange(of: source) { _, newSource in
            chunks = OversizeTextChunker.displayChunks(newSource)
        }
    }
}

// MARK: - Helpers

extension ThemeColor {
    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
