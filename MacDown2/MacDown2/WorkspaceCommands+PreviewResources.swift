import SwiftUI
import Workspace

extension WorkspaceCommands {
    func setPreviewLayout(_ layout: PreviewLayoutMode) {
        coordinator?.setPreviewLayout(layout)
    }

    var previewResourcesCommand: some View {
        Button("Allow preview resources…") {
            coordinator?.allowPreviewResourcesForCurrentDocument()
        }
        .disabled(coordinator?.canAllowPreviewResources != true)
    }
}
