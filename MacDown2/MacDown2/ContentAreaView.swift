import AppKit
import EditorCore
import FileCore
import Highlighting
import JSONSupport
import MarkdownEngine
import OutlineUI
import Preview
import SwiftUI
import Themes
import Workspace

struct ContentAreaView: View {
    @Environment(\.windowCoordinator) private var windowCoordinator
    let model: WorkspaceModel
    let editorStore: EditorTextSystemStore
    let findStore: EditorFindModelStore
    let highlightStore: SyntaxHighlightStore
    let parseStore: MarkdownParseStore
    let jsonAnalysisStore: JSONAnalysisStore
    let themeController: ThemeController
    let outlineController: OutlineController
    let externalFileController: ExternalFileController

    @State private var scrollController = ScrollSyncController()

    var body: some View {
        content(
            for: model.activeDocument,
            tab: model.tabStore.activeTab,
            identity: activeIdentity
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(
        for document: FileCore.FileDocument?,
        tab: WorkspaceTab?,
        identity: String?
    ) -> some View {
        if let document, let tab, let identity {
            documentContent(document, tab: tab, identity: identity)
        } else {
            emptyState
        }
    }

    private var activeIdentity: String? {
        model.tabStore.activeTabID?.uuidString
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { model.activeDocument?.text ?? "" },
            set: { newText in
                model.tabStore.updateActiveDocument { $0.edited(text: newText) }
            }
        )
    }

    private func documentContent(
        _ document: FileCore.FileDocument,
        tab: WorkspaceTab,
        identity: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            documentHeaderBar(document)

            if let phase = windowCoordinator?.exportPhase(for: model) {
                exportProgress(phase)
            }

            ExternalFileStatusView(controller: externalFileController)
            WorkspaceRecoveryRequiredNotice(model: model)

            Divider()

            // Source / preview split
            DocumentEditorSplitView(
                model: model,
                document: document,
                tab: tab,
                identity: identity,
                text: textBinding,
                editorStore: editorStore,
                findStore: findStore,
                highlightStore: highlightStore,
                parseStore: parseStore,
                jsonAnalysisStore: jsonAnalysisStore,
                themeController: themeController,
                scrollController: scrollController,
                outlineController: outlineController
            )
        }
    }

    private func documentHeaderBar(_ document: FileCore.FileDocument) -> some View {
        HStack(spacing: 10) {
            Image(systemName: documentIcon(for: document.format.id))
                .foregroundStyle(.secondary)

            Text(verbatim: title(for: document))
                .font(.system(size: 13, weight: .semibold))

            if document.fileURL == nil {
                Text("— Save As… ⌘⇧S to name this document")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Saving indicator (#57) distinguishes a running save from an idle editor.
            if model.isSavingActiveDocument {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("savingIndicator")
            }

            // FileCore resolves the descriptive Plain Text label. The other
            // names are technical terms, and this value needs no second lookup.
            // Use the resolved display value verbatim in the format badge.
            Text(verbatim: document.format.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func exportProgress(_ phase: ExportPhase) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(verbatim: phase.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            if phase.canRequestCancellation {
                Button("Cancel Export") {
                    windowCoordinator?.cancelExport(for: model)
                }
                .controlSize(.small)
                .accessibilityIdentifier("cancelExportButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exportProgress")
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isCreatingDocument {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.small)

                Text("Creating Document…")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("creatingDocumentNotice")
        } else if case let .openFailed(underlying) = model.lastError {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.orange)

                Text("Couldn't Open File")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text(verbatim: FileOpenFailurePresentation.message(for: underlying))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("openFailedNotice")
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.quaternary)

                Text("No Document")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    ShortcutHint(shortcut: "⌘N", label: Text("New File"))
                    ShortcutHint(shortcut: "⌘O", label: Text("Open File"))
                }
            }
        }
    }

    private func title(for document: FileCore.FileDocument) -> String {
        document.fileURL?.lastPathComponent ?? String(localized: "Untitled")
    }

    private func documentIcon(for formatID: String) -> String {
        let sourceIcons: Set = [
            "javascript", "typescript", "python", "ruby",
            "swift", "c", "bash", "sql",
        ]
        if sourceIcons.contains(formatID) {
            return "chevron.left.forwardslash.chevron.right"
        }
        switch formatID {
        // `doc.richtext`, not `richtext` — the latter is not an SF Symbol and
        // logged "No symbol named 'richtext' found in system symbol set" on
        // every header render, which is what filled the console with errors.
        case "markdown": return "doc.richtext"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        default: return "doc.text"
        }
    }
}

private struct WorkspaceRecoveryRequiredNotice: View {
    let model: WorkspaceModel

    var body: some View {
        if case let .conditionalPublicationRecoveryRequired(url) = model.lastError {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(
                    """
                    A competing version was preserved as \(url.lastPathComponent). \
                    Reveal it, then use Save As to keep this copy.
                    """
                )
                .font(.callout)
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .accessibilityIdentifier("conditionalPublicationRevealButton")
                Button("Save As…") {
                    Task { await model.saveAs() }
                }
                .accessibilityIdentifier("conditionalPublicationSaveAsButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.orange.opacity(0.15))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("conditionalPublicationRecoveryNotice")
        } else if case let .recoveryCleanupRequired(url) = model.lastError {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text("Recovery cleanup for \(url.lastPathComponent) needs attention. Reveal it, retry, or use Save As.")
                    .font(.callout)
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .accessibilityIdentifier("recoveryCleanupRevealButton")
                Button("Retry") {
                    Task { await model.retryRecoveryCleanup() }
                }
                .accessibilityIdentifier("recoveryCleanupRetryButton")
                Button("Save As…") {
                    Task { await model.saveAs() }
                }
                .accessibilityIdentifier("recoveryCleanupSaveAsButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.orange.opacity(0.15))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recoveryCleanupRequiredNotice")
        } else if case let .textNotRepresentable(encodingName) = model.lastError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(verbatim: WorkspaceError.textNotRepresentable(encodingName: encodingName).errorDescription ?? "")
                    .font(.callout)
                Spacer()
                Button("Dismiss") {
                    model.dismissLastError()
                }
                .accessibilityIdentifier("textNotRepresentableDismissButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.orange.opacity(0.15))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("textNotRepresentableNotice")
        } else if case let .saveFailed(underlying) = model.lastError {
            // #57: previously nothing rendered this case at all. A save
            // that failed (permission denied, disk full, a write raced by
            // another process) left the document dirty with no visible
            // explanation — indistinguishable from Save silently doing
            // nothing.
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(verbatim: FileSaveFailurePresentation.message(for: underlying))
                    .font(.callout)
                Spacer()
                Button("Retry") {
                    Task { await model.save() }
                }
                .accessibilityIdentifier("saveFailedRetryButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.red.opacity(0.12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("saveFailedNotice")
        }
    }
}

/// A human-readable description of a failed save. Mirrors
/// `FileOpenFailurePresentation` (`WindowCoordinator+OpenFailure.swift`):
/// `FileStoreError` carries no `LocalizedError` conformance of its own, and
/// the two operations fail for different reasons worded differently ("could
/// not be read" is wrong for a write that failed), so this is a distinct,
/// write-flavoured mapping rather than a shared one (#57).
enum FileSaveFailurePresentation {
    static func message(for error: FileStoreError) -> String {
        switch error {
        case .writeFailed: String(localized: "The file could not be written.")
        case .permissionDenied: String(localized: "MostlyText does not have permission to write this file.")
        case .notRegularFile: String(localized: "This is not a regular file.")
        case .invalidURL: String(localized: "This is not a valid save location.")
        case .fileChangedDuringRead: String(localized: "The file changed on disk while saving. Try again.")
        // Thrown both when the containing folder is gone and when the file
        // itself was deleted/moved/trashed while its folder is untouched —
        // exactly issue #57's headline scenario — so this must not name
        // "folder" specifically (adversarial review finding).
        case .fileMissing:
            String(localized: "The file could not be found. It may have been moved, renamed, or deleted.")
        // `.textNotRepresentable` is intercepted by the model into
        // `WorkspaceError.textNotRepresentable` (which names the attempted
        // encoding); it shares this wording only for switch exhaustiveness.
        case .encodingDetectionFailed, .textNotRepresentable:
            String(localized: "The text could not be written in the file's text encoding.")
        case let .decodingFailed(diagnostics):
            diagnostics.first?.message ?? String(localized: "The file's contents could not be verified after saving.")
        case .conditionalPublicationRecoveryRequired:
            // Unreachable in practice: `workspaceError(for:)`
            // (`WorkspaceModel+SavingSupport.swift`) intercepts this case
            // before it ever becomes `.saveFailed(underlying:)`, mapping it
            // instead to the distinct `WorkspaceError
            // .conditionalPublicationRecoveryRequired(url)` that
            // `WorkspaceRecoveryRequiredNotice` renders with the actual
            // filename. Kept here only for switch exhaustiveness.
            String(localized: "A competing version was preserved separately.")
        case .readFailed:
            String(localized: "The file could not be verified after saving.")
        }
    }
}

// MARK: - Helpers

private struct ShortcutHint: View {
    let shortcut: String
    let label: Text

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            label
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
