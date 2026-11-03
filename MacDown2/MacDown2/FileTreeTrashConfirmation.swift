import FileTree
import Foundation

/// The root generation and source are chosen before presenting the sheet.
/// Confirmation cannot acquire fresh authority after a root/window change.
@MainActor
struct FileTreeTrashConfirmation {
    private let model: FileTreeModel
    private let source: URL
    private let context: FileTreeOperationContext
    private let isOriginOpen: @MainActor () -> Bool

    init(model: FileTreeModel, source: URL, isOriginOpen: @escaping @MainActor () -> Bool) {
        self.model = model
        self.source = source
        context = model.beginOperation()
        self.isOriginOpen = isOriginOpen
    }

    var isCurrent: Bool {
        isOriginOpen() && model.isCurrent(context)
    }

    func run() async throws -> FileTreeOperationResult? {
        try Task.checkCancellation()
        guard isCurrent else { return nil }
        return try await model.moveToTrash(source, context: context)
    }
}
