import FileCore
import Foundation

struct HTMLPreviewDocumentIdentity: Equatable {
    let tabID: UUID?
    let documentID: String
    let recoveryEpoch: UUID
    let fileURL: URL?

    init(_ document: FileCore.FileDocument, tabID: UUID?) {
        self.tabID = tabID
        documentID = document.id
        recoveryEpoch = document.recoveryEpoch
        fileURL = document.fileURL
    }
}
