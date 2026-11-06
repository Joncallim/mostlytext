import CryptoKit
import Foundation

func digest(_ identifiers: [String]) -> String {
    SHA256.hash(data: Data(identifiers.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
}
var records: [[String: Any]] = []
for count in [128, 512, 2048, 4096] {
    var allocator = HeadingAnchorAllocator(reservedIDs: ["a-1", "a-3"])
    let start = ContinuousClock.now
    let identifiers = (0 ..< count).map { _ in allocator.allocate(title: "A") }
    let duration = start.duration(to: .now).components
    precondition(identifiers.last == "a-\(count + 1)")
    precondition(Set(identifiers).count == count)
    let milliseconds = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
    records.append(["count": count, "milliseconds": milliseconds, "sha256": digest(identifiers)])
}
var mixed = HeadingAnchorAllocator(reservedIDs: ["a", "a-1", "section", "cafe\u{301}", "A"])
let titles = ["A", "A-1", "A-2", "a", "Café", "Cafe\u{301}", "!!!", "東京", String(repeating: "漢字", count: 100)]
let identifiers = (0 ..< 2048).map { mixed.allocate(title: titles[($0 * 7 + $0 / 3) % titles.count]) }
precondition(Set(identifiers.map { Data($0.utf8) }).count == identifiers.count)
records.append(["mixedCount": identifiers.count, "sha256": digest(identifiers)])
let bytes = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
print(String(decoding: bytes, as: Unicode.UTF8.self))
