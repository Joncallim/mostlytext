import Foundation

struct MarkdownConversionResult {
    let blocks: [MarkdownBlock]
    let headings: [HeadingItem]
}

/// Prevent the opt-in directive AST from hiding authored Markdown while it is
/// incomplete. Ordinary reference definitions intentionally have no block.
enum DirectiveSourceCoverage {
    static func preservingVisibleContent(
        _ result: MarkdownConversionResult,
        body: String,
        offset: Int,
        ordinary: () -> MarkdownConversionResult
    ) -> MarkdownConversionResult {
        let lines = body.markdownLines()
        let originalBlocks = result.blocks
        guard hasUncoveredContent(lines, offset: offset, blocks: originalBlocks) else { return result }
        let recovered = ordinary()
        return hasUncoveredContent(lines, offset: offset, blocks: originalBlocks, recoveredBy: recovered.blocks) ?
            recovered : result
    }

    /// Top-level ranges are ordered and disjoint. Walk them with the physical
    /// lines once, avoiding a block-by-line search on large documents.
    private static func hasUncoveredContent(
        _ lines: [String],
        offset: Int,
        blocks: [MarkdownBlock],
        recoveredBy ordinary: [MarkdownBlock]? = nil
    ) -> Bool {
        var index = 0
        var ordinaryIndex = 0
        for (localLine, source) in lines.enumerated() {
            let line = localLine + offset + 1
            while index < blocks.count, blocks[index].lineRange.upperBound < line {
                index += 1
            }
            if index < blocks.count, blocks[index].lineRange.contains(line) {
                continue
            }
            guard source.utf8.contains(where: { $0 != 0x20 && $0 != 0x09 }) else { continue }
            guard let ordinary else { return true }
            while ordinaryIndex < ordinary.count, ordinary[ordinaryIndex].lineRange.upperBound < line {
                ordinaryIndex += 1
            }
            if ordinaryIndex < ordinary.count, ordinary[ordinaryIndex].lineRange.contains(line) {
                return true
            }
        }
        return false
    }
}
