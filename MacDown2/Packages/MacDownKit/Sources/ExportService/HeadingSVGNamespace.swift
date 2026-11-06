import Foundation

/// Uppercase ASCII cannot collide with the allocator's lowercase heading IDs.
/// Avoid every exact authored ID/name family without growing a prefix from an
/// unbounded authored value or rescanning the inventory for every candidate.
enum HeadingSVGNamespace {
    static let base = "MTTOC-SVG-"

    static func family(avoiding authored: [String]) -> String {
        let limit = authored.count
        var occupied: Set<Int> = []
        for value in authored where value.utf8.starts(with: base.utf8) {
            var bytes = value.utf8.dropFirst(base.utf8.count).makeIterator()
            guard let first = bytes.next(), (0x30 ... 0x39).contains(first) else { continue }
            var counter = Int(first - 0x30)
            var next = bytes.next()
            if first == 0x30, next != 0x2D {
                continue
            }
            while let byte = next, (0x30 ... 0x39).contains(byte), counter <= limit {
                // Before multiplication the counter is bounded by the admitted
                // inventory, so even a million-digit input cannot overflow.
                counter = counter * 10 + Int(byte - 0x30)
                next = bytes.next()
            }
            if next == 0x2D, counter <= limit {
                occupied.insert(counter)
            }
        }
        var counter = 0
        while occupied.contains(counter) {
            counter += 1
        }
        return base + String(counter) + "-"
    }
}
