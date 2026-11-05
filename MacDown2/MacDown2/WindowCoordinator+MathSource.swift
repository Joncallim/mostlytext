import AppKit
import EditorCore
import Preview
import Workspace

extension WindowCoordinator {
    /// Never creates a parser or editor to make a stale request look current.
    func mathLiveSource(in model: WorkspaceModel, identity: String) -> MathPreviewLiveSource? {
        guard let controller = controllers.first(where: { $0.model === model && !$0.isClosed }),
              controller.model.tabStore.activeTabID?.uuidString == identity,
              let document = controller.model.activeDocument,
              PreviewRouter.previewKind(for: document.format) == .markdown,
              let editor = controller.editorStore.existingSystem(for: identity),
              let parse = controller.parseStore.existingSession(for: identity),
              let parsed = parse.document, let sourceSHA256 = parsed.sourceSHA256,
              let published = parse.publishedText else { return nil }
        return .init(stamp: .init(
            tabIdentity: identity, documentID: document.id, recoveryEpoch: document.recoveryEpoch,
            mutationGeneration: document.mutationGeneration, parseIdentity: parse.identity,
            parsedRevision: parsed.revision, sourceSHA256: sourceSHA256
        ), modelText: document.text, editorText: editor.textView.string, publishedText: published,
        isKeyWindow: Self.mathWindowOwnsKey(controller.window))
    }

    private static func mathWindowOwnsKey(_ window: NSWindow?) -> Bool {
        guard let window, window.attachedSheet == nil, let key = NSApp.keyWindow else { return false }
        // An owned popover can temporarily become key. Another document or
        // a modal sheet cannot inherit this window's source authority.
        return key === window || (key.parent === window && key.sheetParent == nil)
    }

    func showMathSource(in model: WorkspaceModel, identity: String, session: MathPreviewSession,
                        action: MathPreviewSourceAction) {
        guard let location = session.navigationLocation(
            frameID: action.frameID, sourceID: action.sourceID, live: mathLiveSource(in: model, identity: identity)
        ), let controller = controllers.first(where: { $0.model === model && !$0.isClosed }),
        let system = controller.editorStore.existingSystem(for: identity),
        let tabID = model.tabStore.activeTabID else { return }
        let token = folderSearchNavigationDidChange()
        let range = Self.mathSelection(location, diagnostic: action.diagnostic)
        system.selectionSet = EditorSelectionSet(single: range)
        if system.isDetachedFromEditorView {
            session.pendingNavigation = .init(
                frameID: action.frameID,
                sourceID: action.sourceID,
                diagnostic: action.diagnostic,
                token: token
            )
            model.tabStore.setPreviewLayout(.split(fraction: 0.5), for: tabID)
            scheduleSaveSession()
        } else {
            session.pendingNavigation = nil
            system.revealSelection(utf16Range: range, flash: true, animated: true)
            controller.window?.makeFirstResponder(system.textView)
        }
    }

    /// Called by the real editor mount/layout callback. Source, frame and
    /// competing navigation are all checked again after the layout transition.
    func finishMathSourceNavigation(in model: WorkspaceModel, identity: String, session: MathPreviewSession) {
        guard let pending = session.pendingNavigation else { return }
        guard folderSearchNavigationIsCurrent(pending.token), let location = session.navigationLocation(
            frameID: pending.frameID, sourceID: pending.sourceID, live: mathLiveSource(in: model, identity: identity)
        ) else {
            session.pendingNavigation = nil
            return
        }
        guard let controller = controllers.first(where: { $0.model === model && !$0.isClosed }),
              let system = controller.editorStore.existingSystem(for: identity),
              !system.isDetachedFromEditorView else { return }
        session.pendingNavigation = nil
        let range = Self.mathSelection(location, diagnostic: pending.diagnostic)
        system.selectionSet = EditorSelectionSet(single: range)
        system.revealSelection(utf16Range: range, flash: true, animated: true)
        controller.window?.makeFirstResponder(system.textView)
    }

    private static func mathSelection(_ location: MathPreviewSourceLocation, diagnostic: Bool) -> NSRange {
        if diagnostic, let offset = location.diagnosticOffset {
            return .init(location: offset, length: 0)
        }
        return .init(location: location.range.lowerBound, length: location.range.count)
    }
}
