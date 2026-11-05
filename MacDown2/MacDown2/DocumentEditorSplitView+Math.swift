import Foundation
import MarkdownEngine
import Preview
import SwiftUI

extension DocumentEditorSplitView {
    struct MathPresentationTaskID: Equatable {
        let evaluationID: UUID?
        let blocks: [PreviewBlock]?
    }

    var mathTaskID: MathPreviewSourceStamp? {
        coordinator?.mathLiveSource(in: model, identity: identity)?.stamp
    }

    var mathPresentationTaskID: MathPresentationTaskID {
        .init(evaluationID: mathSession.evaluationID, blocks: previewDisplayCache.output)
    }

    var currentMathDisplay: MathPreviewDisplay? {
        guard let display = mathDisplay, let binding = mathSession.binding,
              display.bindingID == binding.id, mathSession.currentFrameID == display.content.id,
              binding.isCurrent(coordinator?.mathLiveSource(in: model, identity: identity)) else { return nil }
        return display
    }

    func refreshMathAnalysis() async {
        mathDisplay = nil
        guard let coordinator, let live = coordinator.mathLiveSource(in: model, identity: identity),
              let document = parseSession.document else {
            mathSession.invalidate()
            return
        }
        let binding = MathPreviewSourceBinding(stamp: live.stamp, source: live.publishedText)
        await mathSession.refresh(binding: binding, document: document) { [weak coordinator, weak model] in
            guard let model else { return nil }
            return coordinator?.mathLiveSource(in: model, identity: identity)
        }
    }

    func refreshMathPresentation() async {
        guard let binding = mathSession.binding, mathSession.evaluationID != nil,
              let document = parseSession.document, let blocks = previewDisplayCache.output,
              binding.isCurrent(coordinator?.mathLiveSource(in: model, identity: identity)) else { return }
        do {
            let display: MathPreviewDisplay = if let evaluation = mathSession.evaluation,
                                                 let presentation = mathSession.presentationPlan,
                                                 !mathSession.analysisFailed {
                try await MathPreviewDisplayBuilder.prepare(.init(
                    source: binding.source, document: document, blocks: blocks,
                    evaluation: evaluation, presentation: presentation
                ), bindingID: binding.id)
            } else {
                MathPreviewDisplayBuilder.fallback(blocks: blocks, bindingID: binding.id)
            }
            installMathDisplay(display)
        } catch is CancellationError {
            // A replacement task owns the next frame; never publish partial work.
        } catch {
            installMathDisplay(MathPreviewDisplayBuilder.fallback(blocks: blocks, bindingID: binding.id))
        }
    }

    private func installMathDisplay(_ display: MathPreviewDisplay) {
        guard !Task.isCancelled, mathSession.installPresentation(
            id: display.content.id, bindingID: display.bindingID, locations: display.locations,
            live: coordinator?.mathLiveSource(in: model, identity: identity)
        ) else { return }
        mathDisplay = display
    }

    func showMathSource(frameID: UUID, sourceID: UUID, diagnostic: Bool) {
        coordinator?.showMathSource(in: model, identity: identity, session: mathSession,
                                    action: .init(frameID: frameID, sourceID: sourceID, diagnostic: diagnostic))
    }
}
