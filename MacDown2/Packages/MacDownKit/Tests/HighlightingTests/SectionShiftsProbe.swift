/// Section count is invariant for the admitted plain-word edits. A Fenwick
/// difference index shifts all later sections in logarithmic time without
/// retaining or scanning one entry per historical edit.
struct SectionShifts {
    private var tree: [Int]

    init(sectionCount: Int) {
        tree = Array(repeating: 0, count: sectionCount + 1)
    }

    mutating func shift(after index: Int, by delta: Int) {
        var slot = index + 2
        while slot < tree.count {
            tree[slot] += delta
            slot += slot & -slot
        }
    }

    func displacement(at index: Int) -> Int {
        var slot = index + 1
        var result = 0
        while slot > 0 {
            result += tree[slot]
            slot -= slot & -slot
        }
        return result
    }
}
