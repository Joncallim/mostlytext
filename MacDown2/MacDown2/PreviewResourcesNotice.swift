import FileCore
import SwiftUI
import Workspace

/// An ungranted Preview remains readable. Only the explicit button or menu can ask for folder access.
struct PreviewResourcesNotice: View {
    let model: WorkspaceModel
    let document: FileCore.FileDocument

    @Environment(\.previewResourceWindowState) private var owner
    @Environment(\.windowCoordinator) private var coordinator

    var body: some View {
        if owner?.hasGrant(for: document) != true {
            HStack(spacing: 8) {
                explanation
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if document.fileURL != nil {
                    Button("Allow preview resources…") {
                        coordinator?.allowPreviewResources(in: model)
                    }
                    .disabled(coordinator?.canAllowPreviewResources(in: model) != true)
                    .accessibilityIdentifier("allowPreviewResources")
                }
            }
            .padding(8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("previewResourcesNotice")
        }
    }

    @ViewBuilder
    private var explanation: some View {
        if document.fileURL == nil {
            Text("Save this document to allow local preview resources.")
        } else if owner?.selectionFailed == true {
            Text("That folder could not be used. Choose the folder containing this document.")
        } else {
            Text("Local preview resources are unavailable.")
        }
    }
}
