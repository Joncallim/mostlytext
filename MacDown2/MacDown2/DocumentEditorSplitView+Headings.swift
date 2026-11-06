import ExportService
import Foundation
import MarkdownEngine
import Preview

extension DocumentEditorSplitView {
    var headingTaskID: PreviewSourceStamp? {
        coordinator?.previewLiveSource(in: model, identity: identity)?.stamp
    }

    var currentHeadingDisplay: HeadingPreviewSession.Display? {
        guard let binding = headingSession.binding,
              previewContributionSession.headingBindingID == binding.id,
              previewDisplayCache.revision == parseSession.document?.revision,
              let composed = previewContributionSession.composition.blocks,
              previewDisplayCache.input == composed,
              !previewContributionSession.composition.diagnostics.contains(where: {
                  $0.contributionID == "toc" && $0.severity == .error
              }),
              let preparation = headingSession.currentPreparation(
                  live: coordinator?.previewLiveSource(in: model, identity: identity)
              ) else { return nil }
        return .init(bindingID: binding.id, preparation: preparation)
    }

    var headingContributionState: PreviewContributionAdapter.HeadingState {
        let live = coordinator?.previewLiveSource(in: model, identity: identity)
        if let preparation = headingSession.currentPreparation(live: live) {
            return .prepared(preparation)
        }
        if headingSession.phase == .failed, headingSession.binding?.isCurrent(live) == true {
            return .unavailable
        }
        return .preparing
    }

    func refreshHeadingAnalysis() async {
        guard let coordinator, let live = coordinator.previewLiveSource(in: model, identity: identity),
              let document = parseSession.document else {
            headingSession.invalidate()
            return
        }
        let candidate = PreviewSourceBinding(stamp: live.stamp, source: live.publishedText)
        await headingSession.refresh(binding: candidate, document: document) { [weak coordinator, weak model] in
            guard let model else { return nil }
            return coordinator?.previewLiveSource(in: model, identity: identity)
        }
    }

    func showHeading(_ action: HeadingPreviewAction) {
        coordinator?.showHeading(
            in: model,
            identity: identity,
            session: headingSession,
            action: action,
            scroll: scrollController
        )
    }
}
