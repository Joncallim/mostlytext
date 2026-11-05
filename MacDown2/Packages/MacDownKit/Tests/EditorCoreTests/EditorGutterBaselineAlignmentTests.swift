import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Regression coverage for a real vertical-misalignment bug: the gutter's
/// line numbers used to be positioned at each `NSTextLayoutFragment`'s own
/// TOP edge (`layoutFragmentFrame.minY`), while the real text glyphs drawn
/// by TextKit are positioned at that fragment's BASELINE -- `glyphOrigin.y`
/// below the top, an offset driven by `EditorConfiguration.lineHeightMultiple`
/// (default 1.2, applied as a base typing attribute in
/// `EditorTextSystem.apply(_:)`), which makes each real line's box TALLER
/// than the font's own natural line height and pushes the baseline down
/// within it. A gutter number drawn at the naive top edge therefore renders
/// measurably HIGHER than the real text's baseline -- exactly the reported
/// symptom (a fresh document's "1" sitting above "one two"'s own baseline).
///
/// These tests verify the INVARIANT the fix establishes -- `enumerateVisibleLineFragments`'s
/// own `baselineY` output equals `layoutFragmentFrame.minY` plus a REAL,
/// TextKit-computed offset, consistent across every line and driven by the
/// actual font/lineHeightMultiple in effect -- rather than a fragile,
/// screenshot-based pixel comparison this project has no reliable way to
/// perform in this environment. Independently re-derives the expected
/// offset via `layoutManager.textLayoutFragment(for:)` at each fragment's
/// own coordinates -- a DIFFERENT TextKit entry point than
/// `enumerateVisibleLineFragments`'s own `enumerateTextLayoutFragments`
/// walk -- rather than merely re-running the same code path.
@MainActor
@Suite("EditorGutterView baseline alignment")
struct EditorGutterBaselineAlignmentTests {
    private let support = EditingAssistIntegrationSupport.self

    private struct MountedSystem {
        let system: EditorTextSystem
        let window: NSWindow
    }

    private func mount(text: String, configuration: EditorConfiguration) -> MountedSystem {
        let system = support.makeSystem(text: text, configuration: configuration)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 1600))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        system.textView.frame = NSRect(x: 0, y: 0, width: 400, height: 1600)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 1600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none // headless tests: window transition animations leak blocked dispatch workers
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        return MountedSystem(system: system, window: window)
    }

    /// Independently recomputes the real baseline for the fragment starting
    /// at `utf16Offset`, using `textLayoutFragment(for:)` -- a lookup by
    /// POINT, not the enumeration `enumerateVisibleLineFragments` itself
    /// walks -- so this is a genuinely separate cross-check, not a restatement
    /// of the same call sequence under test.
    private func independentBaseline(
        forFragmentTopY topY: CGFloat,
        system: EditorTextSystem
    ) -> CGFloat? {
        guard let fragment = system.layoutManager.textLayoutFragment(
            for: CGPoint(x: 1, y: topY + 1)
        ), let firstLine = fragment.textLineFragments.first else { return nil }
        let frame = fragment.layoutFragmentFrame
        return frame.minY + firstLine.typographicBounds.minY + firstLine.glyphOrigin.y
    }

    @Test func firstLineBaselineMatchesTextKitsOwnIndependentlyComputedValue() {
        let mounted = mount(text: "one two", configuration: .default)
        defer { mounted.window.orderOut(nil) }

        var fragments: [(utf16Offset: Int, baselineY: CGFloat)] = []
        mounted.system.enumerateVisibleLineFragments { offset, baselineY in
            fragments.append((offset, baselineY))
        }

        #expect(fragments.count == 1)
        let expected = independentBaseline(forFragmentTopY: 0, system: mounted.system)
        #expect(expected != nil)
        #expect(fragments[0].baselineY == expected)
    }

    @Test func baselineOffsetFromTheFragmentTopIsPositiveAndConsistentAcrossManyLines() throws {
        let lineCount = 50
        let text = (0 ..< lineCount).map { "line \($0)" }.joined(separator: "\n")
        let mounted = mount(text: text, configuration: .default)
        defer { mounted.window.orderOut(nil) }

        var fragments: [(utf16Offset: Int, baselineY: CGFloat)] = []
        mounted.system.enumerateVisibleLineFragments { offset, baselineY in
            fragments.append((offset, baselineY))
        }
        #expect(
            fragments.count == lineCount,
            "expected all \(lineCount) short lines to fit the 1600pt-tall test viewport"
        )

        // Recompute each line's own real fragment top independently (by
        // walking the document from the start, not trusting any value
        // already produced by the method under test) so the "offset from
        // top" comparison below is not comparing a value against itself.
        var frameTops: [CGFloat] = []
        let documentStart = mounted.system.contentStorage.documentRange.location
        mounted.system.layoutManager.enumerateTextLayoutFragments(
            from: documentStart,
            options: [.ensuresLayout]
        ) { fragment in
            frameTops.append(fragment.layoutFragmentFrame.minY)
            return frameTops.count < lineCount
        }
        #expect(frameTops.count == lineCount)

        let offsets = zip(fragments, frameTops).map { $0.baselineY - $1 }
        let first = try #require(offsets.first)
        for offset in offsets {
            // A tolerance, not exact equality: `CGFloat` accumulation across
            // 50 independently-laid-out fragments introduces sub-picopoint
            // rounding noise (e.g. 16.200000000000045 vs. 16.2) that is not
            // drift in any visually or practically meaningful sense.
            #expect(
                abs(offset - first) < 0.001,
                "baseline offset from the fragment's own top must never drift across the document"
            )
        }
        #expect(first > 1, "the offset must be a real, non-negligible ascent distance, not ~0")

        // The regression this fix closes: the OLD code effectively used an
        // offset of 0 (label.minY WAS frame.minY). `lineHeightMultiple`
        // defaults to 1.2, so a genuine fix must produce a strictly
        // positive offset here -- this assertion would have failed against
        // the pre-fix implementation.
        #expect(first != 0)
    }

    @Test func emptyLinesGetTheSameBaselineOffsetAsNonEmptyLines() {
        let mounted = mount(text: "a\n\nb", configuration: .default)
        defer { mounted.window.orderOut(nil) }

        var fragments: [(utf16Offset: Int, baselineY: CGFloat)] = []
        mounted.system.enumerateVisibleLineFragments { offset, baselineY in
            fragments.append((offset, baselineY))
        }
        #expect(fragments.count == 3)

        var frameTops: [CGFloat] = []
        let documentStart = mounted.system.contentStorage.documentRange.location
        mounted.system.layoutManager.enumerateTextLayoutFragments(
            from: documentStart,
            options: [.ensuresLayout]
        ) { fragment in
            frameTops.append(fragment.layoutFragmentFrame.minY)
            return true
        }

        let offsets = zip(fragments, frameTops).map { $0.baselineY - $1 }
        #expect(
            abs(offsets[0] - offsets[1]) < 0.001,
            "the empty middle line must get the same baseline offset as its non-empty neighbors"
        )
        #expect(abs(offsets[1] - offsets[2]) < 0.001)
    }

    @Test func baselineOffsetGrowsWithTheConfiguredLineHeightMultiple() throws {
        var tight = EditorConfiguration.default
        tight.lineHeightMultiple = 1.0
        var loose = EditorConfiguration.default
        loose.lineHeightMultiple = 2.0

        let tightMounted = mount(text: "one", configuration: tight)
        defer { tightMounted.window.orderOut(nil) }
        let looseMounted = mount(text: "one", configuration: loose)
        defer { looseMounted.window.orderOut(nil) }

        var tightBaseline: CGFloat?
        tightMounted.system.enumerateVisibleLineFragments { _, baselineY in tightBaseline = baselineY }
        var looseBaseline: CGFloat?
        looseMounted.system.enumerateVisibleLineFragments { _, baselineY in looseBaseline = baselineY }

        let tightValue = try #require(tightBaseline)
        let looseValue = try #require(looseBaseline)
        #expect(
            looseValue > tightValue,
            "a taller configured line height must push the baseline down further, read from the real config"
        )
    }

    @Test func baselineOffsetChangesWithFontSizeRatherThanUsingAFixedConstant() throws {
        var small = EditorConfiguration.default
        small.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        var large = EditorConfiguration.default
        large.font = NSFont.monospacedSystemFont(ofSize: 30, weight: .regular)

        let smallMounted = mount(text: "one", configuration: small)
        defer { smallMounted.window.orderOut(nil) }
        let largeMounted = mount(text: "one", configuration: large)
        defer { largeMounted.window.orderOut(nil) }

        var smallBaseline: CGFloat?
        smallMounted.system.enumerateVisibleLineFragments { _, baselineY in smallBaseline = baselineY }
        var largeBaseline: CGFloat?
        largeMounted.system.enumerateVisibleLineFragments { _, baselineY in largeBaseline = baselineY }

        let smallValue = try #require(smallBaseline)
        let largeValue = try #require(largeBaseline)
        #expect(largeValue > smallValue, "a larger font must produce a proportionally larger baseline offset")
    }
}
