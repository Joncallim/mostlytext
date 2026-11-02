import CryptoKit
import Dispatch
import Foundation

@main
struct AnchorFingerprintBenchmark {
    static func main() throws {
        var results: [[String: Any]] = []
        for count in [1_048_576, 10_485_760] {
            let source = String(repeating: "a", count: count) + "ÅÅ𝛼"
            let oracle = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
            for kind in ["native", "bridged"] {
                let input = kind == "native" ? source : (source as NSString) as String
                var samples: [Double] = []
                for _ in 0 ..< 3 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let digest = MarkdownSourceFingerprint.sha256(input)
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    guard digest == oracle else { throw BenchmarkError.digestMismatch }
                    samples.append(elapsed)
                }
                results.append([
                    "inputKind": kind, "utf8Bytes": input.utf8.count,
                    "samplesMilliseconds": samples, "medianMilliseconds": samples.sorted()[1],
                    "sha256": oracle,
                ])
            }
        }
        let report: [String: Any] = [
            "scope": "Optimized warm fingerprint component only; no full parse, app, peak-memory or native budget claim",
            "results": results,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    enum BenchmarkError: Error { case digestMismatch }
}
