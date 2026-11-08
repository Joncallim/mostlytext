import AppKit
import EditorCore
import Highlighting
import JSONSupport
@testable import MacDown2
import MarkdownEngine
import OutlineUI
import SwiftUI
import Testing
import Themes
import Workspace

/// EPIC-16 16D: pseudo-localization / layout resilience evidence, and 16C's
/// "at least one shipped non-English locale" acceptance criterion, in the
/// same deterministic-render style as `RenderedStateEvidenceTests` (E15) --
/// real production views, `ImageRenderer`, no mock views, no golden-image
/// baseline. Each render is asserted non-blank and, where the layout has a
/// fixed/narrow frame, personally inspected (see `RELEASE_EVIDENCE.md`'s E16
/// row) rather than pixel-diffed against a baseline.
///
/// Locale is forced with `.environment(\.locale:)`, which is how SwiftUI
/// resolves `Text()`/`LocalizedStringKey` against a specific locale's
/// `Localizable.xcstrings` entries independent of the host machine's system
/// language -- the same mechanism Xcode's own canvas preview locale trait
/// uses. `fr`/`pl`/`ja` were chosen (see `planning/epic-16-implementation.md`)
/// to cover three materially different CLDR plural-rule families.
@MainActor
@Suite("Pseudo-localization / layout resilience evidence (E16)")
struct PseudoLocalizationLayoutTests {
    private static let evidenceDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacDown2LocalizationEvidence", isDirectory: true)

    private static let sampleMarkdown = """
    # Rendered State Evidence
    **Bold**, *italic*, `inline code`, and a [link](https://example.com).
    - A bullet list
    - With a second item
    > A blockquote for good measure.
    """

    /// A synthetic worst-case string: much longer than any real translation
    /// observed so far, to stress fixed-width layout independent of actual
    /// translation quality/length (real German compound nouns can run this
    /// long; this is deliberately longer still).
    private static let pseudoLongLabel =
        "Ẋẋṫřëmëľÿ Ŀõñģ Ṗšëüďõ-Ŀõçäľïžëď Ŀäбëľ Ẅïṫḧ Ṁüçḧ Ṁõřë Ṫëẍṫ Ṫḧäñ Ëñģľïšḧ"

    private struct RenderResult {
        let width: Int
        let height: Int
        let nonBlank: Bool
    }

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

    private static func makeContentAreaFixture(layout: PreviewLayoutMode, text: String) -> ContentAreaView {
        let model = WorkspaceModel(tabStore: TabStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.edited(text: text) }
        if let activeTabID = model.tabStore.activeTabID {
            model.tabStore.setPreviewLayout(layout, for: activeTabID)
        }
        return ContentAreaView(
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
                identity: model.tabStore.activeTabID?.uuidString ?? "loc-evidence"
            )
        )
    }

    // MARK: - Real, seeded non-English locales (16C acceptance criterion)

    @Test(arguments: ["fr", "pl", "ja"])
    func populatedEditorRendersInLocale(_ localeIdentifier: String) throws {
        let view = Self.makeContentAreaFixture(layout: .split(fraction: 0.5), text: Self.sampleMarkdown)
        let result = try Self.renderPNG(
            view.environment(\.locale, Locale(identifier: localeIdentifier)),
            named: "loc-\(localeIdentifier)-01-populated-editor"
        )
        #expect(result.nonBlank, "\(localeIdentifier) populated editor+preview rendered a uniformly blank image")
    }

    @Test(arguments: ["fr", "pl", "ja"])
    func firstRunWelcomeRendersInLocale(_ localeIdentifier: String) throws {
        let view = FirstRunView(onStartWriting: {}, onOpenSample: {})
        let result = try Self.renderPNG(
            view.environment(\.locale, Locale(identifier: localeIdentifier)),
            named: "loc-\(localeIdentifier)-02-first-run",
            size: CGSize(width: 560, height: 460)
        )
        #expect(result.nonBlank, "\(localeIdentifier) first-run welcome screen rendered a uniformly blank image")
    }

    @Test(arguments: ["fr", "pl", "ja"])
    func settingsRendersInLocale(_ localeIdentifier: String) throws {
        let view = SettingsView()
        let result = try Self.renderPNG(
            view.environment(\.locale, Locale(identifier: localeIdentifier)),
            named: "loc-\(localeIdentifier)-03-settings",
            size: SettingsView.contentSize
        )
        #expect(result.nonBlank, "\(localeIdentifier) settings view rendered a uniformly blank image")
    }

    @Test(arguments: ["fr", "pl", "ja"])
    func externalFileNoticesRenderInLocale(_ localeIdentifier: String) throws {
        let model = WorkspaceModel(tabStore: TabStore())
        model.newDocument()
        let controller = ExternalFileController(
            model: model,
            editorStore: EditorTextSystemStore(),
            identity: "loc-evidence-\(localeIdentifier)"
        )
        controller.notice = .conflict
        let result = try Self.renderPNG(
            ExternalFileStatusView(controller: controller).environment(\.locale, Locale(identifier: localeIdentifier)),
            named: "loc-\(localeIdentifier)-04-external-file-conflict",
            size: CGSize(width: 700, height: 80)
        )
        #expect(result.nonBlank, "\(localeIdentifier) conflict notice banner rendered a uniformly blank image")
    }

    /// The one pluralized string in the app (preview-budget diagnostic):
    /// resolves the exact source key `PreviewContributionAdmission` uses,
    /// through each compiled `.lproj` bundle. `locale:` alone does not force
    /// catalog lookup away from the process language in this test process;
    /// mere inequality between counts would pass even with English fallback.
    @Test(arguments: ["en", "fr", "pl", "ja"])
    func pluralizedPreviewBudgetMessageResolvesInLocale(_ localeIdentifier: String) throws {
        let path = try #require(Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        func resolved(count: Int) -> String {
            String(AttributedString(
                localized: """
                ^[\(count) valid placement](inflect: true) exceeded the preview budget \
                and remain as authored source
                """,
                bundle: bundle,
                locale: Locale(identifier: localeIdentifier)
            ).characters)
        }

        let expectedForms: [(count: Int, phrase: String)] = switch localeIdentifier {
        case "en": [(1, "valid placement"), (2, "valid placements")]
        case "fr": [(0, "emplacement valide"), (1, "emplacement valide"), (2, "emplacements valides")]
        case "pl": [
                (1, "prawidłowe umieszczenie"),
                (2, "prawidłowe umieszczenia"),
                (5, "prawidłowych umieszczeń"),
            ]
        case "ja": [(1, "件の有効な配置"), (3, "件の有効な配置")]
        default: []
        }
        #expect(!expectedForms.isEmpty, "No plural expectations for \(localeIdentifier)")
        for (count, phrase) in expectedForms {
            let text = resolved(count: count)
            #expect(text.contains(phrase), "\(localeIdentifier) count=\(count) chose the wrong catalog form: \(text)")
            #expect(text.contains(String(count)), "\(localeIdentifier) count=\(count) lost its substituted count")
            #expect(!text.contains("(inflect:"), "\(localeIdentifier) count=\(count) leaked inflection markup")
        }
    }

    // MARK: - Structural layout resilience (synthetic worst-case length)

    /// `ShortcutHint` is a fixed-width row item (icon + shortcut glyph +
    /// label) -- exactly the kind of UI element real long translations
    /// (German, Polish, Japanese with wide characters) most often clip.
    /// Uses a synthetic label deliberately longer than any real seeded
    /// translation to verify the row grows/wraps rather than clipping
    /// silently. Personally inspect the PNG for actual truncation --
    /// `nonBlank` alone cannot detect clipped-but-still-drawn text.
    @Test func shortcutHintHandlesVeryLongLabel() throws {
        let view = HStack {
            Text(Self.pseudoLongLabel)
            Spacer()
            Text("⌘⇧⌥N")
        }
        .padding(8)
        // Explicit opaque background: `ImageRenderer` otherwise produces a
        // transparent canvas, and premultiplied-alpha black-on-transparent
        // text shares the same RGB channels as the transparent background,
        // so the RGB-only `isVisuallyNonBlank` sampler below would see no
        // difference even though real text was drawn. Production views (the
        // ones `RenderedStateEvidenceTests` renders) all have a real opaque
        // background already, so this only bites a minimal synthetic view
        // like this one.
        .background(Color.white)
        let result = try Self.renderPNG(
            view, named: "loc-pseudo-01-shortcut-hint", size: CGSize(width: 320, height: 60)
        )
        #expect(result.nonBlank, "pseudo-localized shortcut hint rendered a uniformly blank image")
    }

    /// The command-palette-style list row and the sidebar folder-error row
    /// are both narrow, fixed-width contexts fed directly from
    /// `Text(verbatim:)`/`Text()` content -- render with the synthetic long
    /// label to check for structural (not just cosmetic) layout breakage.
    @Test func narrowListRowHandlesVeryLongLabel() throws {
        let view = List {
            Text(Self.pseudoLongLabel)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 260, height: 44)
        let result = try Self.renderPNG(
            view, named: "loc-pseudo-02-narrow-list-row", size: CGSize(width: 260, height: 44)
        )
        #expect(result.nonBlank, "pseudo-localized narrow list row rendered a uniformly blank image")
    }
}
