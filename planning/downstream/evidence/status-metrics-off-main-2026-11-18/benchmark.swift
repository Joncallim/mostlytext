import Foundation
let path = CommandLine.arguments[1]
let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func sample(_ name: String, _ body: () -> Int) {
    var durations: [Double] = []
    var checksum = 0
    for _ in 0..<12 {
        let start = now()
        checksum &+= body()
        durations.append(Double(now() - start) / 1_000_000)
    }
    durations.sort()
    print("\(name) median=\(durations[6]) max=\(durations[11]) checksum=\(checksum)")
}
sample("characterCount") { text.count }
sample("wordCount") {
    var count = 0
    text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
    return count
}
sample("lineEndings") {
    var lf = 0, crlf = 0, cr = 0
    var priorCR = false
    for byte in text.utf8 {
        switch byte {
        case 0x0A:
            if priorCR { crlf += 1; cr -= 1 } else { lf += 1 }
            priorCR = false
        case 0x0D: cr += 1; priorCR = true
        default: priorCR = false
        }
    }
    return lf + crlf + cr
}
print("bytes=\(text.utf8.count) utf16=\(text.utf16.count)")
