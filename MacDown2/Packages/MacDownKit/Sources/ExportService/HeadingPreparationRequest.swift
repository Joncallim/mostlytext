import Foundation
import MarkdownEngine

/// One immutable source/parse/lifetime input to the document's bounded worker.
public struct HeadingPreparationRequest: Sendable {
    public let document: MarkdownDocument
    public let sourceText: String
    public let documentID: String
    public let recoveryEpoch: UUID
    public let sourceGeneration: UInt

    public init(
        document: MarkdownDocument, sourceText: String,
        documentID: String, recoveryEpoch: UUID, sourceGeneration: UInt
    ) {
        self.document = document
        self.sourceText = sourceText
        self.documentID = documentID
        self.recoveryEpoch = recoveryEpoch
        self.sourceGeneration = sourceGeneration
    }

    func prepare() async throws -> HeadingAnchorPreparation {
        try await HeadingAnchorPreparation.prepare(
            document: document, sourceText: sourceText,
            documentID: documentID, recoveryEpoch: recoveryEpoch, sourceGeneration: sourceGeneration
        )
    }
}
