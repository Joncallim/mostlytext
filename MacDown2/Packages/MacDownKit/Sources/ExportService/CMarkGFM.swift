import cmark_gfm
import cmark_gfm_extensions
import CryptoKit
import Foundation

/// How the bridge should treat an authored link/image URL during rendering.
enum URLDisposition: Equatable {
    /// Leave the URL exactly as authored.
    case keep
    /// Replace the URL with a new value (e.g. a content-addressed resource).
    case rewrite(String)
    /// Empty the URL — used to neutralise a dangerous authored scheme.
    case blank
}

/// Isolates every byte of cmark-gfm C interop behind one type.
///
/// The architecture contract (issue #49) requires a *correct* cmark lifecycle:
/// GFM extensions are registered once and attached to the parser before any
/// feed/finish; the parser, node tree, iterator and render buffer are all
/// invocation-local and freed on every path (including thrown errors), never
/// leaked and never shared between calls. This type is that guarantee.
///
/// It is deliberately an `enum` namespace with pure static functions: there is
/// no stored C state, so nothing can outlive a single call.
enum CMarkGFM {
    /// Option bitmask values, forwarded from cmark-gfm.h.
    static let optDefault: Int32 = CMARK_OPT_DEFAULT
    static let optUnsafe: Int32 = CMARK_OPT_UNSAFE
    static let optSmart: Int32 = CMARK_OPT_SMART

    private static let coreExtensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]

    /// Initialize extension setup once for this wrapper. The pinned Swift
    /// package also protects its shared macOS registry with `pthread_once`,
    /// including calls made through swift-markdown.
    private static let extensionsRegistered: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()

    /// Parses `text`, applies `customNodes` and `urlTransformer`, and renders an
    /// HTML fragment.
    ///
    /// `options` is the exact cmark render option bitmask. When it includes
    /// `CMARK_OPT_UNSAFE`, authored raw HTML is preserved and the `tagfilter`
    /// extension (always attached) still strips dangerous tags.
    ///
    /// `urlTransformer` is called for every image/link URL; it runs on the
    /// caller's thread during the single tree walk.
    static func render(
        _ text: String,
        options: Int32,
        customNodes: [CustomNodeSpec] = [],
        headingAnalysis: HeadingAnalysis = .none,
        urlTransformer: ((String, Bool) throws -> URLDisposition)? = nil
    ) throws -> Rendered {
        // `walk` recurses once per nesting level, so a few thousand `>` would
        // overflow a cooperative thread's stack and kill the app. Like the parse
        // engine, run on a dedicated thread with a large, lazily committed stack.
        try OnLargeStack.run {
            try renderOnCurrentThread(
                text, options: options, customNodes: customNodes,
                headingAnalysis: headingAnalysis,
                urlTransformer: urlTransformer
            )
        }
    }

    private static func renderOnCurrentThread(
        _ text: String,
        options: Int32,
        customNodes: [CustomNodeSpec],
        headingAnalysis: HeadingAnalysis,
        urlTransformer: ((String, Bool) throws -> URLDisposition)?
    ) throws -> Rendered {
        // Reading the `static let` runs its initialiser exactly once under the
        // Swift runtime's own lock. `precondition` is not used here because it
        // is stripped in `-Ounchecked` builds, which would drop registration.
        _ = extensionsRegistered

        guard let parser = cmark_parser_new(options) else {
            throw CMarkError.parserCreationFailed
        }
        defer { cmark_parser_free(parser) }

        for name in coreExtensionNames {
            guard let extensionPointer = cmark_find_syntax_extension(name) else { continue }
            cmark_parser_attach_syntax_extension(parser, extensionPointer)
        }

        // Feed from the string's own contiguous UTF-8 storage. `withCString`
        // would copy the whole document to append a NUL terminator that
        // `cmark_parser_feed` never reads, since the length is explicit.
        var source = text
        source.withUTF8 { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { chars in
                cmark_parser_feed(parser, chars, buffer.count)
            }
        }

        guard let root = cmark_parser_finish(parser) else {
            throw CMarkError.parseProducedNoDocument
        }
        defer { cmark_node_free(root) }

        var walkResult = WalkResult(
            headingAnalysis: headingAnalysis,
            markerNonce: headingAnalysis == .marked ? UUID().uuidString : ""
        )
        try transform(root, customNodes: customNodes, urlTransformer: urlTransformer, result: &walkResult)
        guard !walkResult.markerInsertionFailed else { throw CMarkError.renderFailed }

        // tagfilter/table/tasklist rendering reads the parser's extension list,
        // so it must be taken from the parser while it is still alive.
        let extensions = cmark_parser_get_syntax_extensions(parser)
        guard let rendered = cmark_render_html(root, options, extensions) else {
            throw CMarkError.renderFailed
        }
        defer { free(rendered) }

        let html = substitutingDeferredSentinels(walkResult.deferredInline, in: String(cString: rendered))
        return Rendered(
            html: html,
            containsRawHTML: walkResult.sawRawHTML,
            headingLocations: walkResult.headingLocations,
            headingMarkers: walkResult.headingMarkers,
            headingSourceSHA256: headingAnalysis != .none
                ? SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
                : nil
        )
    }

    /// Convenience for callers that only need the HTML fragment.
    static func renderHTML(
        _ text: String,
        options: Int32,
        customNodes: [CustomNodeSpec] = [],
        urlTransformer: ((String, Bool) throws -> URLDisposition)? = nil
    ) throws -> String {
        try render(text, options: options, customNodes: customNodes, urlTransformer: urlTransformer).html
    }
}
