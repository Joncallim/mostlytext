import Foundation
var seed: UInt64 = 0x68276ac4091
func next() -> UInt8 {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return UInt8(truncatingIfNeeded: seed >> 32)
}
var checked = 0
for length in 0 ... 99 {
    for _ in 0 ..< 500 {
        var bytes = (0 ..< length).map { _ in CChar(bitPattern: next()) }
        bytes.append(0)
        bytes.append(contentsOf: [65, 66, 67, 0])
        let old = String(cString: bytes)
        let new = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        precondition(old.utf8.elementsEqual(new.utf8))
        checked += 1
    }
}
print("Exact old/new UTF-8 equality for \(checked) NUL-terminated buffers, including invalid UTF-8 and ignored suffixes")
