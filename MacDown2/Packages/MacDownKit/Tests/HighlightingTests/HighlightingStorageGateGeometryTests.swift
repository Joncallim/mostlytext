import AppKit
@testable import Highlighting
import Testing

@MainActor
@Suite("Highlighting storage gate geometry")
struct HighlightingStorageGateGeometryTests {
    private struct Observation {
        let range: NSRange
        let delta: Int
        let postLength: Int
        let text: String
    }

    @Test func actualReplacementReportsPostMutationUTF16Geometry() {
        let original = "alpha 😀\r\nbeta"
        let storage = NSTextStorage(string: original)
        let gate = HighlightingStorageGate()
        gate.install(on: storage)
        defer { gate.uninstall(from: storage) }
        var observations: [Observation] = []
        gate.didProcessCharacterEditWithGeometry = { range, delta, postLength in
            observations.append(Observation(range: range, delta: delta,
                                            postLength: postLength, text: storage.string))
        }
        let oldRange = (original as NSString).range(of: "beta")

        storage.replaceCharacters(in: oldRange, with: "gamma")

        #expect(observations.count == 1)
        #expect(observations.first?.range == NSRange(location: oldRange.location, length: 5))
        #expect(observations.first?.delta == 1)
        #expect(observations.first?.postLength == ("alpha 😀\r\ngamma" as NSString).length)
        #expect(observations.first?.text == "alpha 😀\r\ngamma")
    }
}
