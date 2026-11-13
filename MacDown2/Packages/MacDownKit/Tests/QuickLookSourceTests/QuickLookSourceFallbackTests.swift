import Darwin
import FileCore
import Foundation
@testable import QuickLookSource
import Testing

struct QuickLookSourceFallbackTests {
    @Test func rendererRefusalAndOversizeExpansionPreserveEscapedSource() throws {
        let source = "<script>authored</script> &"
        let refused = try #require(String(bytes: QuickLookSourceFallback.html(for: source, render: { _ in "" }),
                                          encoding: .utf8))
        let expanded = String(repeating: "x", count: QuickLookSourceFallback.maximumHTMLBytes + 1)
        let oversized = try #require(String(bytes: QuickLookSourceFallback.html(for: source, render: { _ in expanded }),
                                            encoding: .utf8))
        for html in [refused, oversized] {
            #expect(html.contains("&lt;script&gt;authored&lt;/script&gt; &amp;"))
            #expect(!html.contains("<script>"))
            #expect(html.utf8.count <= QuickLookSourceFallback.maximumHTMLBytes)
        }
    }

    @Test func authoredActiveMarkupIsNotExecutedOrFetched() throws {
        let source = "# Head & 😀\r\n<script>alert('x')</script>\n<img src=\"https://example.com/a\">"
        let html = try withFile(Data(source.utf8)) { file in
            try #require(String(bytes: QuickLookSourceFallback.replyHTML(for: file), encoding: .utf8))
        }
        #expect(html.contains("<h1>Head &amp; 😀</h1>"))
        #expect(html.contains("<header>MostlyText</header>"))
        #expect(!html.contains("<script"))
        #expect(!html.contains("<img"))
        #expect(!html.contains("example.com"))
        #expect(html.contains("default-src 'none'; base-uri 'none'; form-action 'none'"))
    }

    @Test func sharedGFMStructureHasNoAuthoredURLs() throws {
        let source = "| Name | Value |\n| --- | --- |\n| one | ~~two~~ |\n\n"
            + "[link](https://example.invalid/page) ![image](https://example.invalid/pixel.png)"
        let html = try withFile(Data(source.utf8)) { file in
            try #require(String(bytes: QuickLookSourceFallback.replyHTML(for: file), encoding: .utf8))
        }
        #expect(html.contains("<table>"))
        #expect(html.contains("<del>two</del>"))
        #expect(html.contains("link"))
        #expect(html.contains("image"))
        #expect(!html.contains("example.invalid"))
    }

    @Test func exactSourceCapIsCompleteAndTheNextByteIsRefused() throws {
        let cap = QuickLookSourceFallback.maximumSourceBytes
        try withFile(Data(repeating: UInt8(ascii: "x"), count: cap)) { file in
            let html = try #require(String(bytes: QuickLookSourceFallback.replyHTML(for: file), encoding: .utf8))
            #expect(html.contains(String(repeating: "x", count: cap)))
        }
        _ = try withFile(Data(repeating: UInt8(ascii: "x"), count: cap + 1)) { file in
            #expect(throws: QuickLookSourceError.sourceTooLarge) {
                try QuickLookSourceFallback.replyHTML(for: file)
            }
        }
    }

    @Test func strictDecodingAcceptsBOMButRejectsMalformedBytes() throws {
        let source = "# 日本語 😀\n"
        let utf16 = try #require(source.data(using: .utf16LittleEndian))
        try withFile(Data([0xFF, 0xFE]) + utf16) { file in
            let html = try #require(String(bytes: QuickLookSourceFallback.replyHTML(for: file), encoding: .utf8))
            #expect(html.contains("<h1>日本語 😀</h1>"))
        }
        _ = try withFile(Data([0xC0, 0xAF])) { file in
            #expect(throws: FileStoreError.self) {
                try QuickLookSourceFallback.replyHTML(for: file)
            }
        }
    }

    @Test func automaticallyDetectableEncodingsAndLineEndingsRenderTheSameUnicodeStructure() throws {
        let source = "# 日本語 😀\n\n| Name | Value |\n| --- | --- |\n| café | مرحبا |\n"
        let reference = try withFile(Data(source.utf8)) { file in
            try QuickLookSourceFallback.replyHTML(for: file)
        }
        let utf16LE = try #require(source.data(using: .utf16LittleEndian))
        let utf16BE = try #require(source.data(using: .utf16BigEndian))
        let variants: [Data] = [
            Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8),
            Data([0xFF, 0xFE]) + utf16LE,
            Data([0xFE, 0xFF]) + utf16BE,
            Data(source.replacingOccurrences(of: "\n", with: "\r\n").utf8),
            Data(source.replacingOccurrences(of: "\n", with: "\r").utf8),
        ]
        for bytes in variants {
            let html = try withFile(bytes) { file in
                try QuickLookSourceFallback.replyHTML(for: file)
            }
            #expect(html == reference)
        }
        let rendered = try #require(String(data: reference, encoding: .utf8))
        #expect(rendered.contains("<h1>日本語 😀</h1>"))
        #expect(rendered.contains("<table>"))
        #expect(rendered.contains("café"))
        #expect(rendered.contains("مرحبا"))
        #expect(!rendered.contains("�"))
    }

    @Test func malformedOrUndeclaredEncodingIsRefusedRatherThanMisrendered() throws {
        let invalidUTF16 = Data([0xFF, 0xFE, 0x00, 0xD8]) // Unpaired high surrogate.
        let legacySingleByte = Data([0x63, 0x61, 0x66, 0xE9]) // No explicit encoding metadata.
        for bytes in [invalidUTF16, legacySingleByte] {
            try withFile(bytes) { file in
                #expect(throws: FileStoreError.self) {
                    try QuickLookSourceFallback.replyHTML(for: file)
                }
            }
        }
    }

    @Test func onlyOneRegularSelectedFileIsAdmitted() throws {
        let remote = try #require(URL(string: "https://example.com/source.md"))
        #expect(throws: QuickLookSourceError.invalidURL) {
            try QuickLookSourceFallback.replyHTML(for: remote)
        }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: QuickLookSourceError.notRegularFile) {
            try QuickLookSourceFallback.replyHTML(for: directory)
        }
        let target = directory.appendingPathComponent("target.md")
        let link = directory.appendingPathComponent("link.md")
        try Data("# Original\n".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: QuickLookSourceError.openFailed) {
            try QuickLookSourceFallback.replyHTML(for: link)
        }
    }

    @Test func transferredDescriptorCannotFollowAReplacedPath() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selectedURL = directory.appendingPathComponent("selected.md")
        let movedURL = directory.appendingPathComponent("moved.md")
        try Data("# Selected\n".utf8).write(to: selectedURL)
        let selected = try QuickLookSourceFallback.openSelectedFile(selectedURL)
        try FileManager.default.moveItem(at: selectedURL, to: movedURL)
        try Data("# Different\n".utf8).write(to: selectedURL)

        let html = try #require(String(bytes: QuickLookSourceFallback.replyHTML(
            forOpenDescriptor: selected.fileDescriptor
        ), encoding: .utf8))
        #expect(html.contains("<h1>Selected</h1>"))
        #expect(!html.contains("Different"))
    }

    @Test func aNamedPipeWithoutAWriterCannotBlockTheProvider() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipe = directory.appendingPathComponent("unwritable.md")
        try #require(mkfifo(pipe.path, S_IRUSR | S_IWUSR) == 0)

        // A separate process owns the potentially blocking call. A regression
        // is killed within the deadline, leaving the test runner responsive.
        let probe = Process()
        probe.executableURL = Bundle(for: TestBundleMarker.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("QuickLookSourceProbe")
        probe.arguments = [pipe.path]
        try probe.run()
        let deadline = Date().addingTimeInterval(2)
        while probe.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if probe.isRunning {
            // A successful exit can race this check; SIGTERM tolerates ESRCH.
            _ = kill(probe.processIdentifier, SIGTERM)
            let graceDeadline = Date().addingTimeInterval(0.2)
            while probe.isRunning, Date() < graceDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if probe.isRunning {
                _ = kill(probe.processIdentifier, SIGKILL)
            }
            let reapDeadline = Date().addingTimeInterval(0.5)
            while probe.isRunning, Date() < reapDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            #expect(!probe.isRunning)
            Issue.record("Quick Look source read blocked on a named pipe without a writer")
        } else {
            #expect(probe.terminationReason == .exit && probe.terminationStatus == 0)
        }
    }

    private func withFile<T>(_ bytes: Data, perform: (URL) throws -> T) throws -> T {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("source.md")
        try bytes.write(to: file)
        return try perform(file)
    }

    private func temporaryDirectory() throws -> URL {
        // /var is a symlink on macOS and the production reader refuses every
        // symlink component, so use the physical temporary directory.
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("mostlytext-ql-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private final class TestBundleMarker: NSObject {}
}
