import AppKit
import FileCore
import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import SwiftUI
import Testing
import Textual
import Themes

/// Controlled image availability, without granting a document directory or altering Textual state.
@Suite("Textual image selection publication", .serialized)
@MainActor
struct TextualImageSelectionPublicationTests {
    @Test func imageReplacementRemainsCopyableAfterAnEarlyNativeCopy() async throws {
        let harness = SecuredMarkdownMountedTests()
        var gates: [SelectionImageBytesGate] = []
        let source = "![fixture](image.png)"
        let references = try (0 ..< 8).map { try coloredPNG(generation: $0) }
        try calibrateOracle(references: references)
        let parsed = try await ParseEngine().parse(source, revision: 1)
        let originalPasteboard = harness.snapshotPasteboard()
        defer { harness.restorePasteboard(originalPasteboard) }
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        let window = harness.makeMountedWindow(hosting: host)
        defer {
            for gate in gates {
                gate.releaseAll()
            }
            window.orderOut(nil)
            window.close()
            PreviewResourceDiagnostics.dump("controlled-selection-publication")
        }
        print("IMAGE_SELECTION_TRACE_ENABLED \(PreviewResourceDiagnostics.isEnabled)")
        for generation in 0 ..< 8 {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            let gate = SelectionImageBytesGate(bytes: references[generation], generation: generation)
            gates.append(gate)
            let previousRequests = gate.requestCount
            let loader = PreviewResourceImageLoader(provider: { _ in await gate.take() })
            host.rootView = AnyView(TextualMarkdownPreview(
                document: parsed, text: source,
                theme: PreviewTheme(theme: BundledThemes.light),
                resourceImageLoader: loader, resourceLoadID: UUID()
            ))
            host.layoutSubtreeIfNeeded()
            let earlyHTML = try await copyWhileBytesAreHeld(in: host, gate: gate, after: previousRequests,
                                                            before: deadline, harness: harness)
            try #require(!matchesCurrentPixels(earlyHTML, reference: references[generation]))
            gate.releaseAll()
            let copiedImage = try await waitForCurrentPixels(in: host, reference: references[generation],
                                                             before: deadline, harness: harness)
            if !copiedImage {
                print("IMAGE_SELECTION_FAILURE generation=\(generation) requests=\(gate.requestCount) "
                    + harness.copyDiagnostics(in: host))
            }
            try #require(copiedImage, "The current image must reach actual native Copy after its bytes are released")
            print("IMAGE_SELECTION_GENERATION \(generation) requests=\(gate.requestCount) copiedPNG=true")
        }
        print("IMAGE_SELECTION_GATE completed=8")
    }

    private func copyWhileBytesAreHeld(
        in host: NSView, gate: SelectionImageBytesGate, after previousRequests: Int,
        before deadline: ContinuousClock.Instant, harness: SecuredMarkdownMountedTests
    ) async throws -> String {
        while gate.requestCount == previousRequests, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(gate.requestCount > previousRequests, "The actual loader must reach the held-byte gate")
        var earlyHTML: String?
        while earlyHTML == nil, ContinuousClock.now < deadline {
            earlyHTML = nativeCopy(in: host, harness: harness)
            if earlyHTML == nil {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        return try #require(earlyHTML, "Actual native Copy must execute before image availability")
    }

    private func channels(generation: Int) -> [CGFloat] {
        [CGFloat((generation >> 2) & 1), CGFloat((generation >> 1) & 1), CGFloat(generation & 1)]
    }

    private func coloredPNG(generation: Int) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let values = channels(generation: generation)
        let color = NSColor(deviceRed: values[0], green: values[1], blue: values[2], alpha: 1)
        for row in 0 ..< 8 {
            for column in 0 ..< 8 {
                bitmap.setColor(color, atX: column, y: row)
            }
        }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func matchesCurrentPixels(_ html: String, reference: Data) -> Bool {
        guard let start = html.range(of: "data:image/png;base64,")?.upperBound else { return false }
        let encoded = html[start...].prefix { $0.isLetter || $0.isNumber || "+/=".contains($0) }
        guard let bytes = Data(base64Encoded: String(encoded)),
              let actual = components(bytes, space: .sRGB), let expected = components(reference, space: .sRGB)
        else { return false }
        return zip(actual, expected).allSatisfy { abs($0 - $1) < 0.1 }
    }

    private func components(_ bytes: Data, space: NSColorSpace) -> [CGFloat]? {
        guard bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let image = NSBitmapImageRep(data: bytes), image.pixelsWide == 8, image.pixelsHigh == 8,
              let color = image.colorAt(x: 0, y: 0)?.usingColorSpace(space)
        else { return nil }
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
    }

    private func calibrateOracle(references: [Data]) throws {
        try #require(references.count == 8)
        for expected in references.indices {
            for actual in references.indices {
                let html = "<img src=\"data:image/png;base64,\(references[actual].base64EncodedString())\">"
                try #require(matchesCurrentPixels(html, reference: references[expected]) == (actual == expected))
            }
        }
        // Exact synthetic PNG copied by the first failed native comparison, not a replacement success result.
        let capturedBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdp"
            + "AAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAACKADAAQAAAABAAAACAAAAACVhHtSAAAAF0lE"
            + "QVQYGWNkYPj/nwEPYMIjB5YaHgoAEF0CDh+PWwkAAAAASUVORK5CYII="
        let captured = try #require(Data(base64Encoded: capturedBase64))
        let capturedHTML = "<img src=\"data:image/png;base64,\(capturedBase64)\">"
        try #require(matchesCurrentPixels(capturedHTML, reference: references[1]))
        print("IMAGE_SELECTION_COLORSPACE device=\(String(describing: components(captured, space: .deviceRGB))) "
            + "capturedSRGB=\(String(describing: components(captured, space: .sRGB))) "
            + "encodedReferenceSRGB=\(String(describing: components(references[1], space: .sRGB))) "
            + "constructor=\(channels(generation: 1))")
        print("IMAGE_SELECTION_ORACLE positives=8 negatives=56 capturedBlue=true")
    }

    private func waitForCurrentPixels(
        in host: NSView, reference: Data, before deadline: ContinuousClock.Instant,
        harness: SecuredMarkdownMountedTests
    ) async throws -> Bool {
        while ContinuousClock.now < deadline {
            if let html = nativeCopy(in: host, harness: harness), matchesCurrentPixels(html, reference: reference) {
                return true
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func nativeCopy(in view: NSView, harness: SecuredMarkdownMountedTests) -> String? {
        guard let interaction = harness.findTextInteraction(in: view) else { return nil }
        NSPasteboard.general.clearContents()
        _ = interaction.perform(NSSelectorFromString("selectAll:"), with: nil)
        _ = interaction.perform(NSSelectorFromString("copy:"), with: nil)
        return NSPasteboard.general.string(forType: .html)
    }
}

@MainActor
private final class SelectionImageBytesGate {
    private let bytes: Data
    private let generation: Int
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0

    init(bytes: Data, generation: Int) {
        self.bytes = bytes
        self.generation = generation
    }

    func take() async -> PreviewImageBytes {
        requestCount += 1
        let request = requestCount
        print(
            "IMAGE_SELECTION_PROVIDER generation=\(generation) request=\(request) entered cancelled=\(Task.isCancelled)"
        )
        await withCheckedContinuation { pending.append($0) }
        print(
            "IMAGE_SELECTION_PROVIDER generation=\(generation) request=\(request) return cancelled=\(Task.isCancelled)"
        )
        return PreviewImageBytes(data: bytes, reservation: 0)
    }

    func releaseAll() {
        let waiting = pending
        print("IMAGE_SELECTION_GATE_RELEASE generation=\(generation) pending=\(waiting.count)")
        pending.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }
}
