import Foundation

/// Ordinary native state can survive an unrelated edit only when source and
/// complete original URL authority are unchanged. Math occurrence IDs belong
/// to one frame; they never inherit an older native attachment/cache identity.
struct PreviewBlockContentIdentity: Hashable {
    private let source: String
    private let markdown: String
    private let baseURL: String?
    private let frameID: UUID?
    private let guarded: Bool
    private let references: [PreviewMathInput.Reference]

    init(source: String, baseURL: URL?, input: PreviewMathInput?, frameID: UUID?, guarded: Bool) {
        self.source = source
        markdown = input?.rewritten ?? source
        self.baseURL = baseURL?.absoluteString
        self.frameID = input?.markers.isEmpty == false ? frameID : nil
        self.guarded = guarded
        references = input?.references ?? []
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.frameID == rhs.frameID, lhs.guarded == rhs.guarded,
              lhs.source.utf8.elementsEqual(rhs.source.utf8), lhs.markdown.utf8.elementsEqual(rhs.markdown.utf8),
              exact(lhs.baseURL, rhs.baseURL), lhs.references.count == rhs.references.count else { return false }
        return zip(lhs.references, rhs.references).allSatisfy { left, right in
            left.range == right.range && left.kind == right.kind &&
                left.destination.utf8.elementsEqual(right.destination.utf8)
        }
    }

    func hash(into hasher: inout Hasher) {
        // String's coarser canonical hash is compatible with exact equality:
        // distinct spellings may collide, but can never compare equal here.
        hasher.combine(source)
        hasher.combine(markdown)
        hasher.combine(baseURL)
        hasher.combine(frameID)
        hasher.combine(guarded)
        for reference in references {
            hasher.combine(reference.range)
            hasher.combine(reference.kind == .link)
            hasher.combine(reference.destination)
        }
    }

    private static func exact(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): left.utf8.elementsEqual(right.utf8)
        default: false
        }
    }
}
