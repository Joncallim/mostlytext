import AppKit
@testable import Preview
import SwiftUI
import Testing
import Textual

private actor AttachmentRecorder {
    private var references: [String] = []

    func record(_ reference: String) {
        references.append(reference)
    }

    func snapshot() -> [String] {
        references
    }
}

private struct ProbeAttachment: Textual.Attachment {
    let description: String

    var body: some View {
        Text(description)
    }

    func sizeThatFits(_: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        CGSize(width: 12, height: 12)
    }
}

private struct RecordingImageLoader: AttachmentLoader {
    let recorder: AttachmentRecorder

    func attachment(
        for url: URL,
        text: String,
        environment _: ColorEnvironmentValues
    ) async throws -> ProbeAttachment {
        await recorder.record(url.relativeString)
        return ProbeAttachment(description: text)
    }
}

@Suite("Pinned Textual image interception")
@MainActor
struct TextualAttachmentInterceptionTests {
    @Test func mountedStructuredTextPassesAuthoredReferencesToTheCustomLoader() async throws {
        let recorder = AttachmentRecorder()
        let source = """
        ![near](images/plot.png)

        ![remote](https://example.invalid/plot.png)

        ![absolute](file:///tmp/plot.png)

        ![authority](//example.invalid/plot.png)
        """
        let document = URL(fileURLWithPath: "/tmp/mostlytext-probe/document.md")
        let view = StructuredText(source, parser: PreviewMarkupParser(baseURL: document))
            .textual.imageAttachmentLoader(RecordingImageLoader(recorder: recorder))
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.animationBehavior = .none
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()

        var references: [String] = []
        for _ in 0 ..< 50 {
            references = await recorder.snapshot()
            if references.count == 4 {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(references.count == 4)
        #expect(references.contains("images/plot.png"))
        #expect(references.contains("https://example.invalid/plot.png"))
        #expect(references.contains("file:///tmp/plot.png"))
        #expect(references.contains("//example.invalid/plot.png"))
    }
}
