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
            let gate = try SelectionImageBytesGate(bytes: coloredPNG(generation: generation), generation: generation)
            gates.append(gate)
            let previousRequests = gate.requestCount
            let loader = PreviewResourceImageLoader(provider: { _ in await gate.take() })
            host.rootView = AnyView(TextualMarkdownPreview(
                document: parsed, text: source,
                theme: PreviewTheme(theme: BundledThemes.light),
                resourceImageLoader: loader, resourceLoadID: UUID()
            ))
            host.layoutSubtreeIfNeeded()
            try await releaseAfterEarlyCopy(in: host, gate: gate, after: previousRequests,
                                            before: deadline, harness: harness)
            var copiedImage = false
            while ContinuousClock.now < deadline {
                if let html = nativeCopy(in: host, harness: harness), matchesCurrentPixels(
                    html,
                    generation: generation
                ) {
                    copiedImage = true
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            if !copiedImage {
                print("IMAGE_SELECTION_FAILURE generation=\(generation) requests=\(gate.requestCount) "
                    + harness.copyDiagnostics(in: host))
            }
            try #require(copiedImage, "The current image must reach actual native Copy after its bytes are released")
            print("IMAGE_SELECTION_GENERATION \(generation) requests=\(gate.requestCount) copiedPNG=true")
        }
        print("IMAGE_SELECTION_GATE completed=8")
    }

    private func releaseAfterEarlyCopy(
        in host: NSView, gate: SelectionImageBytesGate, after previousRequests: Int,
        before deadline: ContinuousClock.Instant, harness: SecuredMarkdownMountedTests
    ) async throws {
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
        _ = try #require(earlyHTML, "Actual native Copy must execute before image availability")
        gate.releaseAll()
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

    private func matchesCurrentPixels(_ html: String, generation: Int) -> Bool {
        guard let start = html.range(of: "data:image/png;base64,")?.upperBound else { return false }
        let encoded = html[start...].prefix { $0.isLetter || $0.isNumber || "+/=".contains($0) }
        guard let bytes = Data(base64Encoded: String(encoded)), let image = NSBitmapImageRep(data: bytes),
              image.pixelsWide == 8, image.pixelsHigh == 8,
              let color = image.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
        else { return false }
        let actual = [color.redComponent, color.greenComponent, color.blueComponent]
        return zip(actual, channels(generation: generation)).allSatisfy { abs($0 - $1) < 0.1 }
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
