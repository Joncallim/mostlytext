import Dispatch
import Foundation
import Markdown
import Yams

/// The parse owner. An actor so work is serialised and OFF the main thread.
/// The ONLY file that imports Markdown and Yams (D1, D3).
public actor ParseEngine: ParseExecuting {
    private var parseSlotIsTaken = false
    private var queuedParses: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []
    private let beforeRequest: (@Sendable (Int) -> Void)?
    private let beforeSynchronousParse: (@Sendable (Int) -> Void)?

    public init() {
        beforeRequest = nil
        beforeSynchronousParse = nil
    }

    init(beforeRequest: @escaping @Sendable (Int) -> Void,
         beforeSynchronousParse: @escaping @Sendable (Int) -> Void) {
        self.beforeRequest = beforeRequest
        self.beforeSynchronousParse = beforeSynchronousParse
    }

    /// Pure: text in → document out.
    public func parse(
        _ text: String,
        options: MarkdownParseOptions = .default,
        revision: Int
    ) async throws -> MarkdownDocument {
        dispatchPrecondition(condition: .notOnQueue(.main))

        try Task.checkCancellation()
        beforeRequest?(revision)

        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await acquireParseSlot(requestID)
            defer { releaseParseSlot() }
            try Task.checkCancellation()

            // swift-markdown, the block converter and Yams all recurse once per
            // nesting level. On a cooperative-pool thread (≈512 KB of stack) a few
            // KB of hostile or accidental input — `>` repeated ~700 times, deeply
            // nested emphasis or lists, a YAML flow sequence ~350 deep — overflows
            // it and kills the app, and a crash during open or session restore
            // repeats on every relaunch. The synchronous work therefore runs on a
            // dedicated thread with a large (lazily committed) stack.
            let document = await Self.runOnLargeStack { [self] in
                parseSynchronously(text, options: options, revision: revision)
            }

            try Task.checkCancellation()
            return document
        } onCancel: {
            Task { await self.cancelQueuedParse(requestID) }
        }
    }

    private func acquireParseSlot(_ requestID: UUID) async throws {
        try Task.checkCancellation()
        if !parseSlotIsTaken {
            parseSlotIsTaken = true
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            queuedParses.append((requestID, continuation))
        }
    }

    private func releaseParseSlot() {
        if queuedParses.isEmpty {
            parseSlotIsTaken = false
        } else {
            let next = queuedParses.removeFirst()
            next.continuation.resume()
        }
    }

    private func cancelQueuedParse(_ requestID: UUID) {
        guard let index = queuedParses.firstIndex(where: { $0.id == requestID }) else { return }
        let canceled = queuedParses.remove(at: index)
        canceled.continuation.resume(throwing: CancellationError())
    }

    /// Stack for the parse thread. Only touched pages are committed.
    static let parseThreadStackSize = 1 << 30

    private nonisolated func parseSynchronously(
        _ text: String,
        options: MarkdownParseOptions,
        revision: Int
    ) -> MarkdownDocument {
        beforeSynchronousParse?(revision)
        let sourceMap = SourceMap(text: text)

        let extraction = FrontMatterExtractor.extract(from: text)
        let bodyText = extraction?.body ?? text
        let bodyLineOffset = extraction?.closingLineNumber ?? 0
        let frontMatter = extraction.map { ext in
            FrontMatter(
                raw: ext.raw,
                lineRange: 1 ... ext.closingLineNumber,
                values: parseYAML(ext.raw)
            )
        }

        // swift-markdown 0.8.0 always enables GFM; only directives are optional.
        var parseOptions: ParseOptions = []
        if options.blockDirectives {
            parseOptions.insert(.parseBlockDirectives)
        }
        let document = Document(parsing: bodyText, options: parseOptions)

        let fallbackRange = 1 ... max(1, sourceMap.lineCount)
        let converter = BlockConverter(bodyLineOffset: bodyLineOffset)
        var result = converter.convert(document, parentRange: fallbackRange)
        if options.blockDirectives {
            result = DirectiveSourceCoverage.preservingVisibleContent(
                result,
                body: bodyText,
                offset: bodyLineOffset
            ) {
                converter.convert(Document(parsing: bodyText), parentRange: fallbackRange)
            }
        }

        let fingerprint = MarkdownSourceFingerprint.sha256(text)
        let facts = sourceFacts(document, original: text, bodyLineOffset: bodyLineOffset, fingerprint: fingerprint)
        return MarkdownDocument(
            body: bodyText,
            bodyLineOffset: bodyLineOffset,
            blocks: result.blocks,
            headings: result.headings,
            frontMatter: frontMatter,
            sourceMap: sourceMap,
            revision: revision,
            options: options,
            sourceSHA256: fingerprint,
            sourceFacts: facts
        )
    }

    private nonisolated func sourceFacts(
        _ document: Document, original: String, bodyLineOffset: Int, fingerprint: String
    ) -> MarkdownSourceFacts? {
        guard !original.utf8.contains(0) else { return nil }
        return MarkdownSourceFactProjection.project(
            source: original, sourceSHA256: fingerprint, root: document as any Markup,
            children: { Array($0.children) }, describe: { node in
                let kind: MarkdownSourceNode.Kind = switch node {
                case is Paragraph, is Heading, is Table.Cell: .container
                case is CodeBlock, is HTMLBlock: .opaque
                case is InlineCode, is InlineHTML, is Image: .literal
                case let link as Link: .link(destination: link.destination, title: link.title)
                case is SoftBreak, is LineBreak: .lineBreak
                case is InlineMarkup: .inline
                default: .other
                }
                let range = node.range.map {
                    MarkdownSourcePoint(line: $0.lowerBound.line + bodyLineOffset, column: $0.lowerBound.column) ..<
                        MarkdownSourcePoint(line: $0.upperBound.line + bodyLineOffset, column: $0.upperBound.column)
                }
                return MarkdownSourceNode(kind: kind, range: range)
            }
        )
    }

    // MARK: - YAML front matter

    private nonisolated func parseYAML(_ raw: String) -> [String: FrontMatterValue]? {
        guard !Self.exceedsYAMLAliasBudget(raw) else { return nil }
        // Yams force-unwraps a mapping key's scalar construction, so a sequence/mapping/alias key
        // (`[ref]: x`, `? [a, b]`, `{a: b}: c`) traps the process. Only load documents whose keys are all scalars.
        guard let tree = try? Yams.compose(yaml: raw), Self.hasOnlyScalarKeys(tree),
              !Self.exceedsYAMLExpansionBudget(tree),
              let root = try? Yams.load(yaml: raw)
        else {
            return nil
        }
        guard let mapping = root as? [String: Any] else {
            return nil
        }
        return mapping.compactMapValues { convertYAMLValue($0) }
    }
}

// MARK: - Block conversion

private struct BlockConverter {
    /// Nesting deeper than this is never authored by hand. The converted tree is
    /// a nested value type that every consumer walks — and whose release —
    /// recurses once per level, on whatever (small) thread drops the last
    /// reference, so the depth is bounded here rather than trusted.
    static let maxDepth = 128

    let bodyLineOffset: Int

    func convert(_ document: Document, parentRange: ClosedRange<Int>) -> MarkdownConversionResult {
        var blocks: [MarkdownBlock] = []
        var headings: [HeadingItem] = []
        let children = document.children.compactMap { $0 as? BlockMarkup }
        // The document's own first line is the first line of the BODY, which sits
        // after any front matter.
        let bodyRange = min(parentRange.upperBound, bodyLineOffset + 1) ... parentRange.upperBound
        let ranges = resolvedRanges(of: children, within: bodyRange)
        for (block, range) in zip(children, ranges) {
            let result = convert(block, range: range, depth: 0)
            blocks.append(result.block)
            headings.append(contentsOf: result.headings)
        }
        return MarkdownConversionResult(blocks: blocks, headings: headings)
    }

    func convert(
        _ node: BlockMarkup,
        range: ClosedRange<Int>,
        depth: Int
    ) -> (block: MarkdownBlock, headings: [HeadingItem]) {
        var childBlocks: [MarkdownBlock] = []
        var headings: [HeadingItem] = []

        if let heading = node as? Heading {
            headings.append(HeadingItem(
                level: heading.level,
                title: heading.plainText,
                lineRange: range
            ))
        }

        if depth < Self.maxDepth {
            let children = node.children.compactMap { $0 as? BlockMarkup }
            let ranges = resolvedRanges(of: children, within: range, clampsToParent: true)
            for (child, childRange) in zip(children, ranges) {
                let result = convert(child, range: childRange, depth: depth + 1)
                childBlocks.append(result.block)
                headings.append(contentsOf: result.headings)
            }
        }
        let code = (node as? CodeBlock)?.code
        return (
            block: MarkdownBlock(kind: kind(for: node), lineRange: range, children: childBlocks, codeContent: code),
            headings: headings
        )
    }

    /// Line ranges for sibling blocks, repaired where swift-markdown 0.8 reports
    /// them wrongly: a paragraph directly followed by a table has NO range (and
    /// the table's range starts on the paragraph's line), and a setext heading
    /// directly followed by another block extends one line into it. Siblings
    /// never overlap, so a missing range is the gap before the next sibling, a
    /// table starts at its header row, and an overlap is clamped to the line
    /// before the next sibling.
    private func resolvedRanges(
        of children: [BlockMarkup],
        within parent: ClosedRange<Int>,
        clampsToParent: Bool = false
    ) -> [ClosedRange<Int>] {
        let ends: [Int?] = children.map { originalLineRange(for: $0)?.upperBound }
        let starts: [Int?] = zip(children, ends).map { child, end in
            let reported = originalLineRange(for: child)?.lowerBound
            // A table's reported range starts at the preceding paragraph's first
            // line. Its real first line is its header row: one line per body row,
            // one delimiter line, then the header.
            if let table = child as? Table, let end {
                return max(reported ?? 1, end - (table.body.childCount + 1))
            }
            return reported
        }

        // The first known start after each sibling, computed once (a per-sibling
        // forward scan would be quadratic on documents with many blocks).
        var nextKnownStart = [Int?](repeating: nil, count: children.count)
        var following: Int?
        for index in children.indices.reversed() {
            nextKnownStart[index] = following
            if let start = starts[index] {
                following = start
            }
        }

        var resolved: [ClosedRange<Int>] = []
        resolved.reserveCapacity(children.count)
        var previousEnd = parent.lowerBound - 1
        for index in children.indices {
            let start = starts[index] ?? (previousEnd + 1)
            let nextStart = nextKnownStart[index]
            var end = ends[index] ?? ((nextStart ?? (parent.upperBound + 1)) - 1)
            if let nextStart, end >= nextStart {
                end = nextStart - 1
            }
            // A child of a container never extends past it. swift-markdown reports an unterminated fence inside a
            // list item or quote as running on through the following item/paragraph.
            if clampsToParent {
                end = min(end, parent.upperBound)
            }
            end = max(start, end)
            resolved.append(start ... end)
            previousEnd = end
        }
        return resolved
    }

    private func kind(for node: BlockMarkup) -> BlockKind {
        if let listKind = listKind(for: node) {
            return listKind
        }

        switch node {
        case is Heading:
            return .heading(level: (node as? Heading)?.level ?? 1)
        case is Paragraph:
            return .paragraph
        case let codeBlock as CodeBlock:
            let language = codeBlock.language.flatMap { languageToken(from: $0) }
            return .codeBlock(language: language)
        case is BlockQuote:
            return .blockQuote
        case let table as Table:
            return .table(columnCount: table.maxColumnCount)
        case is ThematicBreak:
            return .thematicBreak
        case is HTMLBlock:
            return .htmlBlock
        default:
            return .custom(String(describing: type(of: node)))
        }
    }

    private func listKind(for node: BlockMarkup) -> BlockKind? {
        switch node {
        case let orderedList as OrderedList:
            return .orderedList(startIndex: Int(orderedList.startIndex))
        case is UnorderedList:
            return .unorderedList
        case let listItem as ListItem:
            let taskState: BlockKind.TaskState? = listItem.checkbox.map {
                $0 == .checked ? .checked : .unchecked
            }
            return .listItem(taskState: taskState)
        default:
            return nil
        }
    }

    private func languageToken(from infoString: String) -> String? {
        let token = infoString.split(separator: " ", omittingEmptySubsequences: true).first
        return token.map { String($0).lowercased() }
    }

    private func originalLineRange(for node: Markup) -> ClosedRange<Int>? {
        guard let range = node.range else { return nil }
        let startLine = max(1, range.lowerBound.line + bodyLineOffset)
        // swift-markdown SourceRange upperBound is exclusive. When it sits at
        // column 1 it points to the line after the content; otherwise it sits
        // on the content's last line (e.g. a single-line node with no trailing
        // newline reports upperBound.line == lowerBound.line).
        let rawEndLine = range.upperBound.line
        let endLine = max(startLine, (range.upperBound.column == 1 ? rawEndLine - 1 : rawEndLine) + bodyLineOffset)
        return startLine ... endLine
    }
}
