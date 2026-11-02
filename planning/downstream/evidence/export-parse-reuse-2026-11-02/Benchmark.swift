import Foundation
import MarkdownEngine

/// Component timings only: the real parser and frozen adapter, without an app,
/// renderer, files, user stores or a claim about complete Export latency.
@main
struct ExportParseBenchmark {
    struct Sample: Encodable {
        let corpus: String
        let sourceBytes: Int
        let iteration: Int
        let twoParsesMilliseconds: Double
        let oneParseAndReuseMilliseconds: Double
        let checksum: Int
    }

    static func main() async throws {
        let ordinary = "A paragraph with **strong text**, a [link](https://example.com) and café.\n\n"
        let technical = "## Section\n\n> Quoted 雪 and `code`.\n\n```swift\nlet value = 42\n```\n\n<div>static HTML</div>\n\n"
        _ = try await ParseEngine().parse("# Warmup\n", revision: 0)
        var samples: [Sample] = []
        for (name, fragment) in [("ordinary", ordinary), ("technical", technical)] {
            let source = String(repeating: fragment, count: (1 << 20) / fragment.utf8.count + 1)
            for iteration in 1 ... 3 {
                let before: (Double, Int)
                let after: (Double, Int)
                if iteration.isMultiple(of: 2) {
                    after = try await measure(source, revision: iteration, reuse: true)
                    before = try await measure(source, revision: iteration, reuse: false)
                } else {
                    before = try await measure(source, revision: iteration, reuse: false)
                    after = try await measure(source, revision: iteration, reuse: true)
                }
                guard before.1 == after.1 else { throw MeasurementError.changedOutput }
                samples.append(Sample(
                    corpus: name, sourceBytes: source.utf8.count, iteration: iteration,
                    twoParsesMilliseconds: before.0, oneParseAndReuseMilliseconds: after.0, checksum: after.1
                ))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(samples)
        guard let json = String(data: data, encoding: .utf8) else { throw MeasurementError.encoding }
        print("EXPORT_PARSE_TIMINGS " + json)
    }

    private static func measure(_ source: String, revision: Int, reuse: Bool) async throws -> (Double, Int) {
        let clock = ContinuousClock()
        let start = clock.now
        let engine = ParseEngine()
        let first = try await engine.parse(source, revision: revision)
        let second: MarkdownDocument
        if reuse {
            let frozen = FrozenExportParse(text: source, revision: revision, document: first, releaseAfterUse: true)
            second = try await frozen.parse(source, options: .default, revision: revision)
        } else {
            second = try await engine.parse(source, revision: revision)
        }
        let elapsed = start.duration(to: clock.now).components
        guard first == second else { throw MeasurementError.changedOutput }
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        return (milliseconds, second.body.utf8.count + second.headings.count + second.revision)
    }

    private enum MeasurementError: Error {
        case changedOutput
        case encoding
    }
}
