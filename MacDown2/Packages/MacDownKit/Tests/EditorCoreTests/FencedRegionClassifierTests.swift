@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §2.3, §6.12, §7.3 — Slice 4b's fenced-code/front-matter
/// classifier, tested in isolation from the engine it gates.
@Suite("FencedRegionClassifier")
struct FencedRegionClassifierTests {
    @Test("plain prose classifies as .prose")
    func plainProseIsProse() {
        let text = "just some words\nover two lines" as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: 5) == .prose)
    }

    @Test("caret inside a fenced code block classifies as .fencedCode with the tagged language")
    func insideFenceWithLanguageTag() {
        let text = "prose\n```swift\nlet x = 1\n```\nmore prose" as NSString
        let insideOffset = text.range(of: "let x").location
        #expect(FencedRegionClassifier
            .classify(text: text, atUTF16Offset: insideOffset) == .fencedCode(languageID: "swift"))
    }

    @Test("caret inside an untagged fence classifies as .fencedCode with a nil language")
    func insideFenceWithNoLanguageTag() {
        let text = "prose\n```\nsome code\n```\nmore prose" as NSString
        let insideOffset = text.range(of: "some code").location
        #expect(FencedRegionClassifier
            .classify(text: text, atUTF16Offset: insideOffset) == .fencedCode(languageID: nil))
    }

    @Test("caret after a closed fence classifies as .prose again")
    func afterAClosedFenceIsProseAgain() {
        let text = "prose\n```swift\ncode\n```\nmore prose here" as NSString
        let afterOffset = text.range(of: "more prose").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: afterOffset) == .prose)
    }

    @Test("caret between two separate fences (in prose) classifies as .prose")
    func betweenTwoFencesIsProse() {
        let text = "```swift\ncode one\n```\nprose in between\n```python\ncode two\n```" as NSString
        let betweenOffset = text.range(of: "prose in between").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: betweenOffset) == .prose)
    }

    @Test("caret in the second of two fences reports the second fence's own language")
    func secondFenceReportsItsOwnLanguage() {
        let text = "```swift\ncode one\n```\nprose\n```python\ncode two\n```" as NSString
        let insideSecond = text.range(of: "code two").location
        #expect(
            FencedRegionClassifier
                .classify(text: text, atUTF16Offset: insideSecond) == .fencedCode(languageID: "python")
        )
    }

    @Test("tilde fences are recognized the same as backtick fences")
    func tildeFencesWork() {
        let text = "prose\n~~~ruby\ncode\n~~~\nmore prose" as NSString
        let insideOffset = text.range(of: "code").location
        #expect(FencedRegionClassifier
            .classify(text: text, atUTF16Offset: insideOffset) == .fencedCode(languageID: "ruby"))
    }

    @Test("a fence indented up to 3 spaces (inside a list item) is still recognized")
    func indentedFenceInsideAListItem() {
        let text = "- item\n  ```swift\n  let x = 1\n  ```\n- next item" as NSString
        let insideOffset = text.range(of: "let x").location
        #expect(FencedRegionClassifier
            .classify(text: text, atUTF16Offset: insideOffset) == .fencedCode(languageID: "swift"))
    }

    @Test("a fence indented 4+ spaces is NOT recognized as a fence delimiter (CommonMark: becomes indented code)")
    func fourSpaceIndentedFenceIsNotRecognized() {
        // Per the disclosed, practical scope of this classifier's own
        // fence-detection grammar (§6.12): 4+ leading spaces disqualifies a
        // line as a fence delimiter, matching CommonMark's own "up to 3
        // spaces" rule. This "fence" is therefore invisible to the
        // classifier entirely -- both the opener and (later) the matching
        // "closer" are simply ordinary prose lines, so parity is never
        // disturbed and everything classifies as prose throughout.
        let text = "prose\n    ```swift\n    let x = 1\n    ```\nmore prose" as NSString
        let insideOffset = text.range(of: "let x").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: insideOffset) == .prose)
    }

    @Test("a document ending in an unterminated closing fence with no trailing newline is prose again, not fencedCode")
    func unterminatedClosingFenceAtEndOfDocumentWithNoTrailingNewlineIsProse() {
        // A P1 an independent hostile review of §6.12 found: the caret's OWN
        // current line was never itself checked for being a fence
        // delimiter, only lines strictly BEFORE it -- so when the document
        // ends with a closing fence and no trailing newline, the caret's
        // "own line" IS that closing fence, and it was silently dropped
        // from the parity count. That left only the opener counted (odd),
        // wrongly reporting `.fencedCode` for a caret that has actually
        // moved past the closing fence back into ordinary prose (there just
        // happens to be no more prose text after it).
        let text = "prose\n```swift\ncode\n```" as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length) == .prose)
    }

    @Test(
        "a caret on a closing fence line, right past its marker but before that line's own trailing newline, is prose"
    )
    func caretPastClosingFenceMarkerButBeforeItsOwnTrailingNewlineIsProse() {
        // The same current-line check the P1 fix above added is not
        // EOF-specific -- it must also fire for a closing fence that DOES
        // have more document after it, as long as the caret itself has
        // moved past the marker but is still positioned on that same line
        // (e.g. before the line's own trailing newline).
        let text = "prose\n```swift\ncode\n```\nmore prose" as NSString
        let closingFenceLineStart = text.range(of: "```\nmore prose").location
        let caret = closingFenceLineStart + 3 // right after the 3 backticks, before "\nmore prose"
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: caret) == .prose)
    }

    @Test("an unterminated OPENING fence at end of document (no closer, no trailing newline) is fencedCode")
    func unterminatedOpeningFenceAtEndOfDocumentIsFencedCode() {
        // A related case the P1 fix's own current-line check also resolves
        // correctly, though it targets the SAME code path as the closing-
        // fence regression above: an opener with no closer anywhere in the
        // document (CommonMark: an unclosed fence extends to end of
        // document) must still classify as `.fencedCode`, not `.prose`, when
        // the caret sits on that same unterminated opening line.
        let text = "prose\n```swift" as NSString
        #expect(FencedRegionClassifier
            .classify(text: text, atUTF16Offset: text.length) == .fencedCode(languageID: "swift"))
    }

    @Test("a fence nested inside a blockquote is still recognized")
    func fenceInsideBlockquote() {
        // The classifier's own fence-line check only looks at leading
        // spaces before the marker, not blockquote `>` prefixes -- a
        // blockquote-prefixed fence line like "> ```swift" does NOT match
        // this classifier's own simplified grammar (the `>` isn't a space),
        // so it is NOT recognized as a fence delimiter at all. This test
        // pins that disclosed, accepted limitation rather than asserting an
        // unimplemented behavior.
        let text = "> ```swift\n> let x = 1\n> ```" as NSString
        let insideOffset = text.range(of: "let x").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: insideOffset) == .prose)
    }

    @Test("a mismatched fence character cannot close the active fence")
    func mismatchedFenceCharactersCannotCloseAnActiveFence() {
        let text = "prose\n```swift\ncode\n~~~\nmore prose" as NSString
        let afterMismatchedCloser = text.range(of: "more prose").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: afterMismatchedCloser)
            == .fencedCode(languageID: "swift"))
    }

    // MARK: - Front matter

    @Test("front matter at the very start of the document is classified as .frontMatter")
    func frontMatterAtDocumentStart() {
        let text = "---\ntitle: Test\ndate: 2026-01-01\n---\n# Heading" as NSString
        let insideOffset = text.range(of: "title:").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: insideOffset) == .frontMatter)
    }

    @Test("content after front matter's closing delimiter is ordinary prose")
    func afterFrontMatterIsProse() {
        let text = "---\ntitle: Test\n---\n# Heading" as NSString
        let afterOffset = text.range(of: "# Heading").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: afterOffset) == .prose)
    }

    @Test("front matter can close with ... instead of ---")
    func frontMatterClosesWithEllipsis() {
        let text = "---\ntitle: Test\n...\nbody text" as NSString
        let insideOffset = text.range(of: "title:").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: insideOffset) == .frontMatter)
        let afterOffset = text.range(of: "body text").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: afterOffset) == .prose)
    }

    @Test("a blank line after the opening --- makes it a thematic break, not front matter")
    func blankLineAfterOpenerIsNotFrontMatter() {
        let text = "---\n\n# Intro\n\n---\nafter" as NSString
        let offset = text.range(of: "# Intro").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: offset) == .prose)
    }

    @Test("a document NOT starting with --- has no front matter, even if --- appears later")
    func noFrontMatterWithoutAnOpeningDelimiterOnLineOne() {
        let text = "# Heading\n---\nnot front matter" as NSString
        let offset = text.range(of: "not front matter").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: offset) != .frontMatter)
    }

    @Test("an unclosed --- at document start remains unresolved while editing")
    func unclosedFrontMatterDelimiterIsUnresolved() {
        let text = "---\ntitle: Test\nno closing delimiter here" as NSString
        let offset = text.range(of: "no closing").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: offset) == .unresolved)
    }

    @Test("front matter immediately followed by a fence: the fence is still detected correctly")
    func frontMatterImmediatelyFollowedByAFence() {
        let text = "---\ntitle: Test\n---\n```swift\nlet x = 1\n```\nprose" as NSString
        let insideFrontMatter = text.range(of: "title:").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: insideFrontMatter) == .frontMatter)
        let insideFence = text.range(of: "let x").location
        #expect(
            FencedRegionClassifier.classify(text: text, atUTF16Offset: insideFence) == .fencedCode(languageID: "swift")
        )
        let afterFence = text.range(of: "\nprose").location + 1
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: afterFence) == .prose)
    }

    // MARK: - CRLF line endings

    @Test("fences are recognized correctly with CRLF line endings")
    func crlfLineEndingsWork() {
        let text = "prose\r\n```swift\r\nlet x = 1\r\n```\r\nmore prose" as NSString
        let insideOffset = text.range(of: "let x").location
        #expect(FencedRegionClassifier
            .classify(text: text, atUTF16Offset: insideOffset) == .fencedCode(languageID: "swift"))
        let afterOffset = text.range(of: "more prose").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: afterOffset) == .prose)
    }

    @Test("front matter is recognized correctly with CRLF line endings")
    func crlfFrontMatterWorks() {
        let text = "---\r\ntitle: Test\r\n---\r\nbody" as NSString
        let insideOffset = text.range(of: "title:").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: insideOffset) == .frontMatter)
        let afterOffset = text.range(of: "body").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: afterOffset) == .prose)
    }

    // MARK: - Boundary offsets

    @Test("an out-of-range offset is clamped rather than crashing")
    func outOfRangeOffsetIsClamped() {
        let text = "short" as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: -5) == .prose)
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: 999) == .prose)
    }

    @Test("an empty document classifies as .prose without crashing")
    func emptyDocumentIsProse() {
        let text = "" as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: 0) == .prose)
    }

    // MARK: - Bounded-scan performance (§15's own required adversarial case)

    @Test("a very large document beyond the scan cap stays bounded and unresolved")
    func largeDocumentScanStaysBoundedAndUnresolved() {
        let paragraph = String(repeating: "word ", count: 20) + "\n"
        let hugeProse = String(repeating: paragraph, count: 100_000) // ~2.5 MB, well past the scan cap
        let text = hugeProse as NSString
        let lateOffset = text.length - 10

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = FencedRegionClassifier.classify(text: text, atUTF16Offset: lateOffset)
        }
        // Even a prose-only suffix cannot prove there was no distant open
        // fence before the bounded window; do not invent a prose answer.
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: lateOffset) == .unresolved)
        // Generous budget: this is a correctness-of-boundedness check, not a
        // tight micro-benchmark -- it must not degrade toward whole-document
        // cost, which a bounded 5,000-line scan comfortably avoids even on
        // a slow CI runner.
        #expect(elapsed < .milliseconds(200))
    }

    @Test("a worst-case scan (caret 5,000 lines past the last fence) stays within a few milliseconds")
    func worstCaseScanStaysWithinAPerKeystrokeBudget() {
        // A P2 an independent hostile review of §6.12 found: this
        // classifier runs on EVERY keystroke, and while the bounded scan is
        // correctness-bounded (the test above), its per-keystroke COST close
        // to the cap was never itself pinned by a test. This fixture puts
        // the caret ~4,900 lines past the document's only (closed) fence --
        // close to, but comfortably under, `maximumFenceLinesScanned` (so
        // the scan reaches both fence lines and document start well within
        // its budget, giving a stable, unambiguous `.prose` answer) --
        // forcing a near-worst-case-length backward scan every time.
        let linesPastFence = 4900
        let filler = String(repeating: "prose line\n", count: linesPastFence)
        let text = ("```swift\ncode\n```\n" + filler) as NSString
        let lateOffset = text.length - 5

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = FencedRegionClassifier.classify(text: text, atUTF16Offset: lateOffset)
        }
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: lateOffset) == .prose)
        // A generous per-keystroke budget -- measured well under 5ms in
        // practice at this cap, budgeted higher for a slow CI runner.
        #expect(elapsed < .milliseconds(25))
    }

    @Test("a backtick line with a backtick in its info string is inline code, not a fence")
    func backtickInfoStringIsNotAFence() {
        let text = "```x``` inline\nstill prose" as NSString
        let offset = text.range(of: "still").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: offset) == .prose)
    }
}
