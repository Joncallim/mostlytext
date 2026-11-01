import AppKit
import Diagrams
import DiagramsD2
import DiagramsGraphviz
import EditorCore
import FileCore
import Highlighting
import JSONSupport
@testable import MacDown2
import MarkdownEngine
import Math
import MathRendering
import OutlineUI
import Preview
import SwiftUI
import Testing
import Themes
import Workspace

/// E15 deterministic visual evidence, in place of whole-screen capture
/// (blocked in this environment by a hard `audio/video capture failure`
/// and a declined System Settings/VoiceOver Utility grant -- see
/// `RELEASE_EVIDENCE.md`'s E15 row). Every state here is rendered from a
/// real production view via SwiftUI's `ImageRenderer` -- the same engine
/// `MathImageRenderer.swift` already uses in shipping code for math
/// export -- never a screenshot and never a test-only mock view.
///
/// PNGs are written to `FileManager.default.temporaryDirectory/
/// MacDown2RenderEvidence/` and deliberately not cleaned up, so a human
/// (or a later automated pass) can open and look at exactly what these
/// tests certify was rendered. There is no golden-image baseline: adding
/// a snapshot-diffing dependency and a baseline-maintenance burden was
/// judged not worth it for a first pass, so each test instead asserts the
/// render actually produced a non-trivial image (correct size, not a
/// uniformly blank canvas) -- real, if modest, regression coverage for
/// "this view silently stopped rendering anything," not a claim that
/// every layout detail is pixel-verified.
@MainActor
@Suite("Rendered state evidence (E15)")
struct RenderedStateEvidenceTests {
    private static let evidenceDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacDown2RenderEvidence", isDirectory: true)

    private static let sampleMarkdown = """
    # Rendered State Evidence

    **Bold**, *italic*, `inline code`, and a [link](https://example.com).

    - A bullet list
    - With a second item

    > A blockquote for good measure.

    ```swift
    let x = 1
    ```

    | A | B |
    |---|---|
    | 1 | 2 |
    """

    private struct RenderResult {
        let width: Int
        let height: Int
        let nonBlank: Bool
    }

    /// Renders `view` at a fixed, concrete size (most production views here
    /// use `.frame(maxWidth: .infinity, ...)`, which has no intrinsic size
    /// for `ImageRenderer` to lay out into on its own) and writes the
    /// result as a PNG. Returns the pixel dimensions so callers can assert
    /// on them.
    @discardableResult
    private static func renderPNG(
        _ view: some View,
        named name: String,
        size: CGSize = CGSize(width: 900, height: 600),
        scale: CGFloat = 2
    ) throws -> RenderResult {
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return RenderResult(width: 0, height: 0, nonBlank: false)
        }
        guard let pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            Issue.record("Could not encode PNG for \(name)")
            return RenderResult(width: cgImage.width, height: cgImage.height, nonBlank: false)
        }
        try pngData.write(to: evidenceDirectory.appendingPathComponent("\(name).png"))
        return RenderResult(width: cgImage.width, height: cgImage.height, nonBlank: isVisuallyNonBlank(cgImage))
    }

    /// Writes raw PNG bytes already produced by a real renderer (math,
    /// Mermaid) directly to the evidence directory, without a second
    /// `ImageRenderer` pass.
    private static func writePNG(_ data: Data, named name: String) throws {
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try data.write(to: evidenceDirectory.appendingPathComponent("\(name).png"))
    }

    /// A coarse, sparse-sampled "is this a solid single color" check --
    /// enough to catch a view that silently rendered nothing (a blank
    /// canvas) without needing a full pixel-diff baseline.
    private static func isVisuallyNonBlank(_ cgImage: CGImage) -> Bool {
        guard let data = cgImage.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return false }
        let length = CFDataGetLength(data)
        guard length >= 4 else { return false }
        let first = (ptr[0], ptr[1], ptr[2])
        var index = 0
        while index + 4 <= length {
            if (ptr[index], ptr[index + 1], ptr[index + 2]) != first {
                return true
            }
            index += 4 * 37
        }
        return false
    }

    private struct ContentAreaFixture {
        let view: ContentAreaView
    }

    private static func makeContentAreaFixture(layout: PreviewLayoutMode, text: String) -> ContentAreaFixture {
        let model = WorkspaceModel(tabStore: TabStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.edited(text: text) }
        if let activeTabID = model.tabStore.activeTabID {
            model.tabStore.setPreviewLayout(layout, for: activeTabID)
        }
        let view = ContentAreaView(
            model: model,
            editorStore: EditorTextSystemStore(),
            findStore: EditorFindModelStore(),
            highlightStore: SyntaxHighlightStore(),
            parseStore: MarkdownParseStore(),
            jsonAnalysisStore: JSONAnalysisStore(),
            themeController: ThemeController(),
            outlineController: OutlineController(),
            externalFileController: ExternalFileController(
                model: model,
                editorStore: EditorTextSystemStore(),
                identity: model.tabStore.activeTabID?.uuidString ?? "evidence"
            )
        )
        return ContentAreaFixture(view: view)
    }

    // MARK: - Editor / preview states

    @Test func emptyEditorStateRenders() throws {
        let fixture = Self.makeContentAreaFixture(layout: .editorOnly, text: "")
        let result = try Self.renderPNG(fixture.view, named: "01-empty-editor")
        #expect(result.width == 1800 && result.height == 1200)
    }

    @Test func populatedMarkdownEditorStateRenders() throws {
        let fixture = Self.makeContentAreaFixture(layout: .split(fraction: 0.5), text: Self.sampleMarkdown)
        let result = try Self.renderPNG(fixture.view, named: "02-populated-editor-split")
        #expect(result.width == 1800 && result.height == 1200)
        #expect(result.nonBlank, "populated editor+preview split rendered a uniformly blank image")
    }

    @Test func previewOnlyStateRenders() throws {
        let fixture = Self.makeContentAreaFixture(layout: .previewOnly, text: Self.sampleMarkdown)
        let result = try Self.renderPNG(fixture.view, named: "03-preview-only")
        #expect(result.nonBlank, "preview-only rendered a uniformly blank image")
    }

    @Test func populatedEditorDarkModeStateRenders() throws {
        let fixture = Self.makeContentAreaFixture(layout: .split(fraction: 0.5), text: Self.sampleMarkdown)
        let result = try Self.renderPNG(
            fixture.view.environment(\.colorScheme, .dark),
            named: "04-populated-editor-dark"
        )
        #expect(result.nonBlank, "dark-mode editor+preview rendered a uniformly blank image")
    }

    /// `colorSchemeContrast`/`accessibilityReduceMotion` are read-only
    /// mirrors of the real system setting in this SDK (SwiftUI does not
    /// expose a `WritableKeyPath` for either -- confirmed by trying it and
    /// letting the compiler reject it, not assumed), so Increase Contrast
    /// and Reduce Motion cannot be forced for a deterministic render
    /// without actually toggling System Settings, which this session does
    /// not have access to (see `RELEASE_EVIDENCE.md`). `legibilityWeight`
    /// (Bold Text) and `dynamicTypeSize` (larger accessibility text sizes)
    /// ARE genuinely settable per-view accessibility conditions, so this
    /// test exercises those instead -- real, controllable accessibility
    /// evidence in place of the two that are not.
    @Test func populatedEditorBoldTextStateRenders() throws {
        let fixture = Self.makeContentAreaFixture(layout: .split(fraction: 0.5), text: Self.sampleMarkdown)
        let result = try Self.renderPNG(
            fixture.view.environment(\.legibilityWeight, .bold),
            named: "05-populated-editor-bold-text"
        )
        #expect(result.nonBlank, "bold-text (legibilityWeight) editor+preview rendered a uniformly blank image")
    }

    @Test func populatedEditorAccessibilityLargeTextStateRenders() throws {
        let fixture = Self.makeContentAreaFixture(layout: .split(fraction: 0.5), text: Self.sampleMarkdown)
        let result = try Self.renderPNG(
            fixture.view.dynamicTypeSize(.accessibility3),
            named: "06-populated-editor-accessibility-large-text"
        )
        #expect(result.nonBlank, "accessibility-large-text editor+preview rendered a uniformly blank image")
    }

    // MARK: - First-run and settings

    @Test func firstRunWelcomeStateRenders() throws {
        let view = FirstRunView(onStartWriting: {}, onOpenSample: {})
        let result = try Self.renderPNG(view, named: "07-first-run-welcome", size: CGSize(width: 560, height: 460))
        #expect(result.nonBlank, "first-run welcome screen rendered a uniformly blank image")
    }

    @Test func settingsStateRenders() throws {
        let view = SettingsView()
        let result = try Self.renderPNG(view, named: "08-settings", size: SettingsView.contentSize)
        #expect(result.nonBlank, "settings view rendered a uniformly blank image")
    }

    // MARK: - Notices / errors

    @Test func externalFileConflictNoticeStateRenders() throws {
        let model = WorkspaceModel(tabStore: TabStore())
        model.newDocument()
        let controller = ExternalFileController(
            model: model,
            editorStore: EditorTextSystemStore(),
            identity: "evidence-conflict"
        )
        controller.notice = .conflict
        let result = try Self.renderPNG(
            ExternalFileStatusView(controller: controller),
            named: "09-external-file-conflict-notice",
            size: CGSize(width: 700, height: 80)
        )
        #expect(result.nonBlank, "conflict notice banner rendered a uniformly blank image")
    }

    @Test func externalFileUnavailableNoticeStateRenders() throws {
        let model = WorkspaceModel(tabStore: TabStore())
        model.newDocument()
        let controller = ExternalFileController(
            model: model,
            editorStore: EditorTextSystemStore(),
            identity: "evidence-unavailable"
        )
        controller.notice = .unavailable(.missingOrMoved)
        let result = try Self.renderPNG(
            ExternalFileStatusView(controller: controller),
            named: "10-external-file-unavailable-notice",
            size: CGSize(width: 700, height: 80)
        )
        #expect(result.nonBlank, "unavailable notice banner rendered a uniformly blank image")
    }

    // MARK: - Math (via the real production renderer, not a re-implementation)

    @Test func mathInlineAndDisplayStatesRender() throws {
        let context = ExportMathRenderContext(foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0, pixelScale: 2)
        let inline = MathSpan(range: 0 ..< 1, style: .inline, latex: "E = mc^2")
        let display = MathSpan(range: 0 ..< 1, style: .display, latex: "\\int_0^\\infty e^{-x}\\,dx = 1")

        let inlineImage = try MathImageRenderer.render(span: inline, context: context)
        try Self.writePNG(inlineImage.pngData, named: "11-math-inline")
        #expect(inlineImage.logicalWidth > 0 && inlineImage.logicalHeight > 0)

        let displayImage = try MathImageRenderer.render(span: display, context: context)
        try Self.writePNG(displayImage.pngData, named: "12-math-display")
        #expect(displayImage.logicalWidth > 0 && displayImage.logicalHeight > 0)
    }

    // MARK: - Diagrams (via the real shared renderers -- genuine WebKit/subprocess output)

    @Test func mermaidDiagramStateRenders() async throws {
        let fence = MermaidFence(
            source: "graph LR\n  A[Write] --> B[Preview]\n  B --> C[Export]",
            sourceRange: 0 ..< 0
        )
        let context = MermaidRenderContext(
            foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
            backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
        )
        let rendered = try await MermaidPreviewRenderer.shared.render(fence, context: context)
        let pngData = try #require(rendered.pngData, "Mermaid renderer produced no PNG snapshot")
        try Self.writePNG(pngData, named: "13-mermaid-diagram")
        #expect(rendered.naturalWidth > 0 && rendered.naturalHeight > 0)
    }

    @Test func d2DiagramStateRenders() async throws {
        let fence = D2Fence(source: "Write -> Preview -> Export", sourceRange: 0 ..< 0)
        let context = D2RenderContext(
            foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
            backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
        )
        let rendered = try await D2PreviewRenderer.shared.render(fence, context: context)
        let image = try #require(NSImage(data: Data(rendered.svg.utf8)), "D2's SVG output did not decode as an image")
        let result = try Self.renderPNG(
            Image(nsImage: image).resizable().scaledToFit(),
            named: "14-d2-diagram",
            size: CGSize(width: 640, height: 400)
        )
        #expect(result.nonBlank, "D2 diagram rendered a uniformly blank image")
    }

    @Test func graphvizDiagramStateRenders() async throws {
        let fence = GraphvizFence(source: "digraph { Write -> Preview -> Export }", sourceRange: 0 ..< 0)
        let context = GraphvizRenderContext(
            foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
            backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
        )
        let rendered = try await GraphvizPreviewRenderer.shared.render(fence, context: context)
        let image = try #require(
            NSImage(data: Data(rendered.svg.utf8)),
            "Graphviz's SVG output did not decode as an image"
        )
        let result = try Self.renderPNG(
            Image(nsImage: image).resizable().scaledToFit(),
            named: "15-graphviz-diagram",
            size: CGSize(width: 640, height: 400)
        )
        #expect(result.nonBlank, "Graphviz diagram rendered a uniformly blank image")
    }
}
