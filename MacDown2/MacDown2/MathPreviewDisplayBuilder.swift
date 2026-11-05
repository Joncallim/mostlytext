import Foundation
import Math
import MathRendering
import Preview
import Textual

struct MathPreviewDisplay: Sendable {
    let bindingID: UUID
    let content: PreviewMathContent
    let notices: [MathPreviewNotice]
    let locations: [UUID: MathPreviewSourceLocation]
}

/// Native work follows exact-source planning. Yield between equations so a
/// newer edit can cancel this complete frame before it becomes authoritative.
@MainActor
enum MathPreviewDisplayBuilder {
    static func prepare(_ request: MathPreviewSourceRequest, bindingID: UUID) async throws -> MathPreviewDisplay {
        var plan = try await MathPreviewSourcePlanner.prepare(request)
        var attachments: [UUID: AnyAttachment] = [:]
        for entry in plan.drawableEntries {
            try Task.checkCancellation()
            await Task.yield()
            guard case let .accepted(body) = entry.outcome else { continue }
            do {
                _ = try MathImageRenderer.admittedSize(body: body, style: entry.equation.syntax.style)
                attachments[entry.id] = AnyAttachment.math(
                    body: body, style: entry.equation.syntax.style == .inline ? .inline : .display,
                    sourceID: entry.id
                ).withAccessibility(.init(
                    label: MathDiagnosticText.equationLabel(
                        body.source, isDisplay: entry.equation.syntax.style != .inline
                    ), actionID: entry.id, actionName: MathDiagnosticText.sourceAction
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let kind: MathEquationDiagnostic.Kind = switch error as? MathRenderError {
                case .noVisibleOutput: .noVisibleOutput
                case .resourceLimit: .resourceLimit
                default: .renderingFailed
                }
                plan.notices.append(MathPreviewSourcePlanner.notice(
                    .init(equationID: entry.id, kind: kind,
                          sourceOffset: entry.equation.syntax.bodyRange.lowerBound), document: request.document
                ))
            }
        }
        try Task.checkCancellation()
        let blocks = plan.blocks.mapValues { block -> PreviewMathContent.Block in
            switch block {
            case let .parsed(input): .parsed(input)
            case .literal: .literal
            }
        }
        return .init(bindingID: bindingID, content: .init(blocks: blocks, attachments: attachments),
                     notices: plan.notices, locations: plan.locations)
    }

    static func fallback(blocks: [PreviewBlock], bindingID: UUID) -> MathPreviewDisplay {
        let notice = MathPreviewNotice(id: UUID(), message: MathDiagnosticText.previewAnalysisUnavailable,
                                       kind: .internalFailure, sourceID: nil)
        let literals = blocks.reduce(into: [UUID: PreviewMathContent.Block]()) { $0[$1.id] = .literal }
        return .init(bindingID: bindingID, content: .init(blocks: literals), notices: [notice], locations: [:])
    }
}
