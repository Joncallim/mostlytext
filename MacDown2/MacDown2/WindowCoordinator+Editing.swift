import AppKit
import EditorCore
import FileCore
import JSONSupport

// MARK: - Markdown formatting command bridge

/// E10 command seam between the SwiftUI menu (`WorkspaceCommands`) and the
/// active editor's `EditorTextSystem`.
///
/// The bridge repeats every safety guard itself; menu enablement via
/// `canPerformMarkdownEditingCommand` is convenience, not a safety boundary.
extension WindowCoordinator {
    /// `true` when the key window's active document is Markdown, its editor
    /// text system exists with assists enabled, and the editor text view is
    /// the first responder — i.e. a formatting command would apply to the
    /// active editor rather than a stale selection.
    var canPerformMarkdownEditingCommand: Bool {
        // Establish an Observation dependency on AppKit focus changes. The
        // value itself is intentionally not used for the responder decision.
        _ = commandStateRevision
        guard let controller = keyMarkdownEditingController,
              let textView = controller.activeEditorTextSystem?.textView
        else { return false }
        return NSApp.keyWindow?.firstResponder === textView
    }

    /// Applies a Markdown formatting command to the key window's active
    /// editor. Returns `false` when any guard fails (including the text
    /// system's own disabled configuration).
    @discardableResult
    func performMarkdownEditingCommand(_ command: MarkdownEditingCommand) -> Bool {
        guard let controller = keyMarkdownEditingController,
              let textSystem = controller.activeEditorTextSystem
        else { return false }

        // Do not apply a formatting command to a stale selection when focus
        // is in the sidebar, Find UI, or another native tab.
        guard NSApp.keyWindow?.firstResponder === textSystem.textView else { return false }

        return textSystem.performMarkdownCommand(command)
    }

    /// The key window's controller whose active tab is in Markdown Syntax Mode
    /// (the file's own format, or a Syntax Mode override) and whose editor text
    /// system exists.
    private var keyMarkdownEditingController: WindowController? {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              controller.model.tabStore.activeTab?.syntaxFormat.id == "markdown",
              controller.activeEditorTextSystem != nil
        else { return nil }
        return controller
    }
}

// MARK: - JSON formatting command bridge

/// E11 Gate 2 command seam: `Format JSON` and `Format JSON with Sorted Keys`.
///
/// The computation runs off the main actor against an immutable snapshot;
/// the result is applied only when the document and editor still match the
/// command-time baseline (an edit, external reload, or any document
/// transition during formatting discards the stale result).
extension WindowCoordinator {
    /// `true` when the key window's active document is JSON and its editor
    /// text system exists, and the analysis session's latest verdict covers
    /// the current text and is valid. Invalid JSON disables the commands —
    /// they would have nothing to format.
    var canPerformJSONFormatting: Bool {
        _ = commandStateRevision
        guard let controller = keyJSONController,
              let document = controller.model.activeDocument
        else { return false }
        guard let session = controller.jsonAnalysisSessionForActiveTab else { return false }
        guard let result = session.result else { return false }
        return result.isValid && result.text.isExactlyEqual(to: document.text)
    }

    /// Formats the key window's active JSON document.
    /// Returns `false` when any guard fails or the document is invalid.
    @discardableResult
    func performJSONFormatting(sortKeys: Bool) async -> Bool {
        guard let controller = keyJSONController,
              let document = controller.model.activeDocument,
              let textSystem = controller.activeEditorTextSystem
        else { return false }
        // Never format over marked (IME) text: it would commit or cancel the composition.
        guard textSystem.canApplyCommandEdit else { return false }

        let snapshotText = textSystem.text
        let baseline = JSONFormattingBaseline(
            text: snapshotText,
            documentGeneration: document.mutationGeneration,
            editorContentRevision: textSystem.contentRevision,
            options: JSONFormatOptions(sortKeys: sortKeys)
        )

        // Compute off the main actor; the result is pure and Sendable.
        let outcome = await Task.detached(priority: .userInitiated) {
            JSONFormatter.format(snapshotText, options: baseline.options)
        }.value

        // Reject stale completions: the document or editor moved past the
        // baseline while formatting ran.
        guard let currentDocument = controller.model.activeDocument,
              let currentSystem = controller.activeEditorTextSystem,
              baseline.accepts(
                  text: currentSystem.text,
                  documentGeneration: currentDocument.mutationGeneration,
                  editorContentRevision: currentSystem.contentRevision
              ),
              currentSystem.canApplyCommandEdit // a composition may have started while formatting ran
        else { return false }

        switch outcome {
        case .invalid:
            // Invalid JSON produces a diagnostic and no formatting; the
            // commands are disabled in this state anyway.
            return false
        case let .formatted(formattedText):
            // Deterministic formatting of an already-formatted document
            // changes nothing: skip the edit so no undo entry, binding
            // publication, or dirty transition occurs.
            guard formattedText != snapshotText else { return true }
            currentSystem.applyDocumentReplacement(
                formattedText,
                undoActionName: sortKeys ? String(localized: "Format JSON with Sorted Keys") :
                    String(localized: "Format JSON")
            )
            return true
        }
    }

    /// The key window's controller whose active document is JSON and whose
    /// editor text system exists.
    private var keyJSONController: WindowController? {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              controller.model.activeDocument?.format.id == "json",
              controller.activeEditorTextSystem != nil
        else { return nil }
        return controller
    }
}

private extension WindowController {
    /// The editor text system of the active tab, if one exists yet.
    var activeEditorTextSystem: EditorTextSystem? {
        guard let activeTab = model.tabStore.activeTab else { return nil }
        return editorStore.existingSystem(for: activeTab.id.uuidString)
    }

    /// The JSON analysis session of the active tab, if one exists yet.
    var jsonAnalysisSessionForActiveTab: JSONAnalysisSession? {
        guard let activeTab = model.tabStore.activeTab else { return nil }
        return jsonAnalysisStore.existingSession(for: activeTab.id.uuidString)
    }
}
