/// Source observed by text analysis. Swift String equality is canonical; analysis
/// snapshots must instead notice every change to the author's exact UTF-8 bytes.
struct SourceAnalysisText: Equatable, Sendable {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text.utf8.elementsEqual(rhs.text.utf8)
    }
}
