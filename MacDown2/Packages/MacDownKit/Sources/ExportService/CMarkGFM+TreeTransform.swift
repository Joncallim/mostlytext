import cmark_gfm
import Foundation

extension CMarkGFM {
    // MARK: - Tree transformation

    /// Facts gathered while walking the tree, so the composer never needs a
    /// second pass over the document to learn them.
    struct WalkResult {
        let headingAnalysis: HeadingAnalysis
        let markerNonce: String
        var sawRawHTML = false
        var insideImageDescription = false
        var headingLocations: [HeadingLocation] = []
        var headingMarkers: [HeadingMarker] = []
        var markerInsertionFailed = false
        /// Inline contributions in a parent that refuses custom inline nodes (a GFM table cell): the sentinel
        /// text stays in the tree and is replaced in the rendered HTML instead.
        var deferredInline: [CustomNodeSpec] = []
    }

    /// A manual recursive walk (not a cmark iterator) so that leaf nodes — in
    /// particular `TEXT`, which the iterator never exits — can be mutated
    /// safely. The next sibling is captured before any mutation; replaced
    /// nodes are never recursed into because their replacements are already
    /// fully built and clean.
    static func transform(
        _ root: UnsafeMutablePointer<cmark_node>,
        customNodes: [CustomNodeSpec],
        urlTransformer: ((String, Bool) throws -> URLDisposition)?,
        result: inout WalkResult
    ) throws {
        let blockSpecs = Dictionary(uniqueKeysWithValues: customNodes.filter(\.isBlock).map { ($0.sentinel, $0) })
        let inlineSpecs = InlineSentinelIndex(customNodes.filter { !$0.isBlock })
        try walk(
            root,
            blockSpecs: blockSpecs,
            inlineSpecs: inlineSpecs,
            urlTransformer: urlTransformer,
            result: &result
        )
    }

    private static func walk(
        _ node: UnsafeMutablePointer<cmark_node>,
        blockSpecs: [String: CustomNodeSpec],
        inlineSpecs: InlineSentinelIndex,
        urlTransformer: ((String, Bool) throws -> URLDisposition)?,
        result: inout WalkResult
    ) throws {
        if result.headingAnalysis != .none, cmark_node_get_type(node) == CMARK_NODE_HEADING {
            let location = HeadingLocation(
                level: Int(cmark_node_get_heading_level(node)),
                line: Int(cmark_node_get_start_line(node)),
                column: Int(cmark_node_get_start_column(node))
            )
            result.headingLocations.append(location)
            if result.headingAnalysis == .marked {
                let comment = "<!--MT117-\(result.markerNonce)-\(result.headingMarkers.count)-->"
                guard let markerNode = cmark_node_new(CMARK_NODE_CUSTOM_INLINE) else {
                    result.markerInsertionFailed = true
                    return
                }
                let configured = comment.withCString { cmark_node_set_on_enter(markerNode, $0) }
                guard configured != 0, cmark_node_prepend_child(node, markerNode) != 0 else {
                    cmark_node_free(markerNode)
                    result.markerInsertionFailed = true
                    return
                }
                result.headingMarkers.append(HeadingMarker(location: location, comment: comment))
            }
        }
        let wasInsideDescription = result.insideImageDescription
        try applyNodePolicy(node, urlTransformer: urlTransformer, result: &result)
        if cmark_node_get_type(node) == CMARK_NODE_IMAGE {
            result.insideImageDescription = true
        }
        defer { result.insideImageDescription = wasInsideDescription }

        var child = cmark_node_first_child(node)
        while let current = child {
            let next = cmark_node_next(current)
            let childKind = cmark_node_get_type(current)

            if childKind == CMARK_NODE_TEXT {
                // Text nodes are leaves; there is nothing below them to walk.
                substituteInlineSentinels(current, inlineSpecs: inlineSpecs, result: &result)
            } else if childKind == CMARK_NODE_PARAGRAPH,
                      let spec = blockSpec(for: current, bySentinel: blockSpecs) {
                replace(current, withCustom: spec)
            } else {
                try walk(
                    current,
                    blockSpecs: blockSpecs,
                    inlineSpecs: inlineSpecs,
                    urlTransformer: urlTransformer,
                    result: &result
                )
            }

            child = next
        }
    }

    /// Rewrites one node's URL when it is an image or link, and notes authored
    /// raw HTML when it is not.
    ///
    /// The node type is read as the cmark enum rather than its string name: the
    /// string form allocates a Swift `String` for every node in the document,
    /// which is the hot path of a large export.
    private static func applyNodePolicy(
        _ node: UnsafeMutablePointer<cmark_node>,
        urlTransformer: ((String, Bool) throws -> URLDisposition)?,
        result: inout WalkResult
    ) throws {
        let kind = cmark_node_get_type(node)
        if kind == CMARK_NODE_HTML_BLOCK || kind == CMARK_NODE_HTML_INLINE {
            result.sawRawHTML = true
            return
        }
        guard kind == CMARK_NODE_IMAGE || kind == CMARK_NODE_LINK,
              !result.insideImageDescription,
              let urlTransformer, let url = cmark_node_get_url(node) else {
            return
        }

        switch try urlTransformer(String(cString: url), kind == CMARK_NODE_IMAGE) {
        case .keep:
            break
        case let .rewrite(replacement):
            _ = replacement.withCString { cmark_node_set_url(node, $0) }
        case .blank:
            _ = "".withCString { cmark_node_set_url(node, $0) }
        }
    }

    /// Returns the spec for a block sentinel when `node` is a paragraph whose
    /// only child is a text node holding exactly that sentinel.
    private static func blockSpec(
        for node: UnsafeMutablePointer<cmark_node>,
        bySentinel: [String: CustomNodeSpec]
    ) -> CustomNodeSpec? {
        guard !bySentinel.isEmpty else { return nil }
        guard let firstChild = cmark_node_first_child(node) else { return nil }
        guard cmark_node_next(firstChild) == nil else { return nil }
        guard cmark_node_get_type(firstChild) == CMARK_NODE_TEXT else { return nil }
        guard let literal = cmark_node_get_literal(firstChild) else { return nil }
        guard let spec = bySentinel[String(cString: literal)] else { return nil }
        return spec
    }

    /// Replaces every inline sentinel inside a text node, splitting the node into
    /// a sequence of text nodes and custom inline nodes. A no-op when the text
    /// holds no sentinel.
    private static func substituteInlineSentinels(
        _ node: UnsafeMutablePointer<cmark_node>,
        inlineSpecs: InlineSentinelIndex,
        result: inout WalkResult
    ) {
        guard !inlineSpecs.isEmpty, let literal = cmark_node_get_literal(node) else { return }
        let value = String(cString: literal)

        guard acceptsCustomInline(beside: node) else {
            var cursor = value.startIndex
            while let found = inlineSpecs.firstMatch(in: value, from: cursor) {
                result.deferredInline.append(found.spec)
                cursor = found.range.upperBound
            }
            return
        }

        if let spec = inlineSpecs.specsBySentinel[value] {
            replace(node, withCustom: spec)
            return
        }

        // `pending` is the start of the text run not yet emitted; every match
        // ends strictly after it starts, so the walk always advances.
        var pieces: [Piece] = []
        var pending = value.startIndex
        while let found = inlineSpecs.firstMatch(in: value, from: pending) {
            if pending < found.range.lowerBound {
                pieces.append(.text(String(value.unicodeScalars[pending ..< found.range.lowerBound])))
            }
            pieces.append(.custom(found.spec))
            pending = found.range.upperBound
        }

        // No sentinel matched: leave the node exactly as parsed.
        guard !pieces.isEmpty else { return }
        if pending < value.endIndex {
            pieces.append(.text(String(value.unicodeScalars[pending...])))
        }

        guard let firstSpec = pieces.first else { return }
        let first = makeNode(for: firstSpec)
        // Insert the whole sequence into the tree before `node`, one node at a
        // time, then unlink and free the original. Building the chain outside
        // the tree first would be undone by `insert_before`, which unlinks its
        // sibling and clears its sibling pointers.
        cmark_node_insert_before(node, first)
        var last = first
        for piece in pieces.dropFirst() {
            let nextNode = makeNode(for: piece)
            cmark_node_insert_after(last, nextNode)
            last = nextNode
        }
        cmark_node_unlink(node)
        cmark_node_free(node)
    }

    private static func makeNode(for piece: Piece) -> UnsafeMutablePointer<cmark_node> {
        switch piece {
        case let .text(string):
            guard let node = cmark_node_new(CMARK_NODE_TEXT) else {
                fatalError("cmark node allocation failed")
            }
            _ = string.withCString { cmark_node_set_literal(node, $0) }
            return node
        case let .custom(spec):
            guard let node = cmark_node_new(CMARK_NODE_CUSTOM_INLINE) else {
                fatalError("cmark node allocation failed")
            }
            setCustomHTML(spec.html, on: node)
            return node
        }
    }

    /// Whether `node`'s parent allows a custom inline sibling. A GFM table cell does not: `cmark_node_replace`
    /// there fails, and freeing the node it failed to unlink would leave a dangling child (and an empty cell).
    private static func acceptsCustomInline(beside node: UnsafeMutablePointer<cmark_node>) -> Bool {
        guard let probe = cmark_node_new(CMARK_NODE_CUSTOM_INLINE) else { return false }
        let accepted = cmark_node_insert_before(node, probe) != 0
        if accepted {
            cmark_node_unlink(probe)
        }
        cmark_node_free(probe)
        return accepted
    }

    private static func replace(_ node: UnsafeMutablePointer<cmark_node>, withCustom spec: CustomNodeSpec) {
        let nodeType: cmark_node_type = spec.isBlock ? CMARK_NODE_CUSTOM_BLOCK : CMARK_NODE_CUSTOM_INLINE
        guard let custom = cmark_node_new(nodeType) else { return }
        setCustomHTML(spec.html, on: custom)
        guard cmark_node_replace(node, custom) != 0 else {
            cmark_node_free(custom)
            return
        }
        // `cmark_node_replace` unlinks `node` but does not free it; the node
        // tree is freed wholesale by the root's `cmark_node_free`, which will
        // not reach this unlinked node.
        cmark_node_free(node)
    }

    /// cmark copies both strings, so the C buffers only need to outlive the call.
    private static func setCustomHTML(_ html: String, on node: UnsafeMutablePointer<cmark_node>) {
        _ = html.withCString { cmark_node_set_on_enter(node, $0) }
        _ = "".withCString { cmark_node_set_on_exit(node, $0) }
    }

    private enum Piece {
        case text(String)
        case custom(CustomNodeSpec)
    }
}
