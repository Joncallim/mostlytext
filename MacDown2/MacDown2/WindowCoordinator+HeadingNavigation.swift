import AppKit
import EditorCore
import Preview
import Workspace

extension WindowCoordinator {
    func showHeading(
        in model: WorkspaceModel, identity: String, session: HeadingPreviewSession,
        action: HeadingPreviewAction, scroll: ScrollSyncController
    ) {
        guard let heading = session.navigationHeading(
            bindingID: action.bindingID, heading: action.heading, identity: action.identity,
            live: previewLiveSource(in: model, identity: identity)
        ), let controller = controllers.first(where: { $0.model === model && !$0.isClosed }),
        let system = controller.editorStore.existingSystem(for: identity) else { return }
        let token = folderSearchNavigationDidChange()
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !system.isDetachedFromEditorView, system.textView.window === controller.window {
            let source = heading.sourceUTF16Range
            let range = NSRange(location: source.lowerBound, length: source.count)
            system.selectionSet = EditorSelectionSet(single: range)
            system.revealSelection(utf16Range: range, flash: true, animated: animated)
        }
        // Preserve Preview-only layout and the current first responder. The
        // deferred SwiftUI scroll gets fresh authority when it is consumed.
        typealias Validation = @MainActor @Sendable () -> Bool
        let validate: Validation = { [weak self, weak model, weak session, weak controller] in
            guard let self, let model, let session, let controller,
                  controllers.contains(where: { $0 === controller && !$0.isClosed }),
                  folderSearchNavigationIsCurrent(token) else { return false }
            return session.navigationHeading(
                bindingID: action.bindingID, heading: action.heading, identity: action.identity,
                live: previewLiveSource(in: model, identity: identity)
            ) != nil
        }
        scroll.queueHeadingJump(toLine: heading.sourceLineRange.lowerBound, animated: animated, validate: validate)
    }
}
