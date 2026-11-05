import Preview

/// Caches the last unchanged preview snapshot. The parsed revision is
/// the primary key; the displayed block array is also part of the key because
/// contributions can publish a new composition without reparsing the source.
/// Keeping this as a small value type makes invalidation explicit and keeps
/// display composition on the main actor that owns the SwiftUI state.
struct PreviewDisplayCache {
    private(set) var revision: Int?
    private(set) var input: [PreviewBlock]?
    private(set) var output: [PreviewBlock]?

    mutating func update(
        revision: Int?,
        blocks: [PreviewBlock]?,
        preprocess: ([PreviewBlock]?) -> [PreviewBlock]? = { $0 }
    ) {
        guard let blocks else {
            reset()
            return
        }
        guard self.revision != revision || input != blocks else { return }
        self.revision = revision
        input = blocks
        output = preprocess(blocks)
    }

    mutating func reset() {
        revision = nil
        input = nil
        output = nil
    }
}
