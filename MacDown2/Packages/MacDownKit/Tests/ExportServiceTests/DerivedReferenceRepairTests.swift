@testable import ExportService
import Foundation
import MarkdownEngine
import Testing

@Suite("Derived label replacements preserve original reference identity")
struct DerivedReferenceRepairTests {
    private func range(_ value: String, in source: String) throws -> Range<Int> {
        let found = (source as NSString).range(of: value, options: .literal)
        try #require(found.location != NSNotFound)
        return found.location ..< NSMaxRange(found)
    }

    private func fragment(_ range: Range<Int>, generation: UInt = 1,
                          diagnostics: [ExportDiagnostic] = []) -> ExportDerivedContribution {
        ExportDerivedContribution(sourceRange: range, placement: .inline,
                                  html: "<span class=\"math\">rendered equation</span>",
                                  sourceGeneration: generation, diagnostics: diagnostics)
    }

    private func render(_ result: DerivedContentComposer.Result) throws -> String {
        try CMarkGFM.render(result.splicedBody, options: CMarkGFM.optDefault, customNodes: result.customNodes).html
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func actualCMarkExportPreservesCollapsedShortcutAndMultilineReferenceTargets(ending: String) async throws {
        for suffix in ["", "[]", "[key]"] {
            let key = suffix == "[key]" ? "key" : "$x$"
            let source = "[$x$]" + suffix + ending + ending + "[" + key + "]:" + ending +
                "  /target" + ending + "  \"title\""
            let document = try await ParseEngine().parse(source, revision: 1)
            let facts = try #require(document.sourceFacts)
            let result = try DerivedContentComposer.compose(
                bodyText: source, bodyStartOffset: 0, sourceUTF16Length: source.utf16.count,
                contributions: [fragment(range("$x$", in: source))], sourceGeneration: 1,
                referenceContext: .init(source: source, facts: facts)
            )
            let html = try render(result)
            #expect(html.contains("<a href=\"/target\" title=\"title\">"))
            #expect(html.contains("<span class=\"math\">rendered equation</span>"))
            #expect(!html.contains("E12INLINE"))
            #expect(result.diagnostics.isEmpty)
        }
    }

    @Test func unqualifiedLabelSubstitutionDemonstrablyLosesItsReference() async throws {
        let source = "[$x$][]\n\n[$x$]: /target \"title\""
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let contribution = try fragment(range("$x$", in: source))
        let broken = DerivedContentComposer.compose(bodyText: source, bodyStartOffset: 0,
                                                    sourceUTF16Length: source.utf16.count,
                                                    contributions: [contribution], sourceGeneration: 1)
        #expect(try !render(broken).contains("href=\"/target\""))
        let repaired = DerivedContentComposer.compose(bodyText: source, bodyStartOffset: 0,
                                                      sourceUTF16Length: source.utf16.count,
                                                      contributions: [contribution], sourceGeneration: 1,
                                                      referenceContext: .init(source: source, facts: facts))
        #expect(try render(repaired).contains("href=\"/target\" title=\"title\""))
    }

    @Test func unmatchedBacktickStaysLiteralWhenTheRawReferenceKeyIsRestored() async throws {
        let source = "[$x$`tail][]\n\n[$x$`tail]: /target \"title\""
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let result = try DerivedContentComposer.compose(bodyText: source, bodyStartOffset: 0,
                                                        sourceUTF16Length: source.utf16.count,
                                                        contributions: [fragment(range("$x$", in: source))],
                                                        sourceGeneration: 1,
                                                        referenceContext: .init(source: source, facts: facts))
        let html = try render(result)
        #expect(html.contains("href=\"/target\" title=\"title\""))
        #expect(html.contains("rendered equation</span>`tail"))
        #expect(!html.contains("<code>"))
    }

    @Test func aReferenceInsideATableKeepsItsTargetAndInlineDerivedFragment() async throws {
        let source = "| A | B |\n|---|---|\n| [$x$][] | other |\n\n[$x$]: /target \"title\""
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let result = try DerivedContentComposer.compose(bodyText: source, bodyStartOffset: 0,
                                                        sourceUTF16Length: source.utf16.count,
                                                        contributions: [fragment(range("$x$", in: source))],
                                                        sourceGeneration: 1,
                                                        referenceContext: .init(source: source, facts: facts))
        let html = try render(result)
        #expect(html
            .contains("<td><a href=\"/target\" title=\"title\"><span class=\"math\">rendered equation</span></a></td>"))
        #expect(html.contains("<td>other</td>"))
        #expect(!html.contains("E12INLINE"))
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func quoteContinuationAndScalarAdjacentKeysSurviveTheRealExportBridge(ending: String) async throws {
        let source = "> - [漢\u{600}$x$\u{301}" + ending + ">   rest][]\u{200C}" + ending + ending +
            "[漢\u{600}$x$\u{301} rest]: /target \"title\""
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        #expect(facts.links.map(\.destination) == ["/target"])
        let result = try DerivedContentComposer.compose(bodyText: source, bodyStartOffset: 0,
                                                        sourceUTF16Length: source.utf16.count,
                                                        contributions: [fragment(range("$x$", in: source))],
                                                        sourceGeneration: 1,
                                                        referenceContext: .init(source: source, facts: facts))
        let html = try render(result)
        #expect(html.contains("href=\"/target\" title=\"title\""))
        #expect(html.contains("rendered equation"))
        #expect(html.contains("\u{200C}"))
    }

    @Test func frontMatterOffsetsAndLaterHeadingCoordinatesIncludeReferenceEdits() async throws {
        let source = "---\ntitle: Doc\n---\n\n[$x$][]\n\n[$x$]: /target\n\n# Later\n"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let bodyOffset = source.utf16.count - document.body.utf16.count
        let result = try DerivedContentComposer.compose(
            bodyText: document.body, bodyStartOffset: bodyOffset, sourceUTF16Length: source.utf16.count,
            contributions: [fragment(range("$x$", in: source))], sourceGeneration: 1,
            recordCoordinates: true, referenceContext: .init(source: source, facts: facts)
        )
        let coordinates = try #require(result.coordinates)
        let originalHeading = try range("# Later", in: document.body)
        let renderedHeading = try range("# Later", in: result.splicedBody)
        #expect(coordinates.renderedOffset(forOriginalOffset: originalHeading.lowerBound) == renderedHeading.lowerBound)
        #expect(coordinates.renderedOffset(forOriginalOffset: document.body.utf16.count) == result.splicedBody.utf16
            .count)
        #expect(try render(result).contains("href=\"/target\""))
    }

    @Test func rejectedFragmentsKeepTheOriginalReferenceAndDoNotAddRepairs() async throws {
        let source = "[$x$][]\n\n[$x$]: /target"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        for contribution in try [
            fragment(range("$x$", in: source), generation: 2),
            fragment(range("$x$", in: source), diagnostics: [.init(severity: .error, message: "injected failure")]),
        ] {
            let result = DerivedContentComposer.compose(bodyText: source, bodyStartOffset: 0,
                                                        sourceUTF16Length: source.utf16.count,
                                                        contributions: [contribution], sourceGeneration: 1,
                                                        referenceContext: .init(source: source, facts: facts))
            #expect(result.splicedBody.utf8.elementsEqual(source.utf8))
            #expect(result.customNodes.isEmpty)
            #expect(try render(result).contains("href=\"/target\""))
        }
    }

    @Test func foreignFactsAndCollidingSuffixEditsRejectTheDerivedSnapshot() async throws {
        let source = "[$x$][]\n\n[$x$]: /target"
        let other = try await ParseEngine().parse(source + "changed", revision: 1)
        let real = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(real.sourceFacts)
        let label = try #require(facts.links.first?.labelRange)
        let suffix = label.upperBound ..< (label.upperBound + 1)
        for (context, contributions) in try [
            (DerivedContentComposer.ReferenceContext(source: source, facts: #require(other.sourceFacts)),
             [fragment(range("$x$", in: source))]),
            (.init(source: source, facts: facts),
             [fragment(range("$x$", in: source)), fragment(suffix)]),
        ] {
            let result = DerivedContentComposer.compose(bodyText: source, bodyStartOffset: 0,
                                                        sourceUTF16Length: source.utf16.count,
                                                        contributions: contributions, sourceGeneration: 1,
                                                        referenceContext: context)
            #expect(result.splicedBody.utf8.elementsEqual(source.utf8))
            #expect(result.customNodes.isEmpty)
            #expect(result.diagnostics.contains { $0.severity == .error })
        }
    }

    @Test func expandedReferenceInputOverBudgetPreservesAuthoredBodyBeforeRendering() async throws {
        let source = "[$x$][]\n\n[$x$]: /target"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let standard = ExportResourceBudget.standard
        let budget = ExportResourceBudget(
            maxSourceUTF8Bytes: standard.maxSourceUTF8Bytes, maxResourceCount: standard.maxResourceCount,
            maxSingleResourceBytes: standard.maxSingleResourceBytes,
            maxAggregateResourceBytes: standard.maxAggregateResourceBytes,
            maxDerivedFragmentCount: standard.maxDerivedFragmentCount,
            maxAggregateDerivedHTMLBytes: standard.maxAggregateDerivedHTMLBytes,
            maxPreparedHTMLUTF8Bytes: source.utf8.count
        )
        let result = try DerivedContentComposer.compose(
            bodyText: source, bodyStartOffset: 0, sourceUTF16Length: source.utf16.count,
            contributions: [fragment(range("$x$", in: source))], sourceGeneration: 1,
            budget: budget, referenceContext: .init(source: source, facts: facts)
        )
        #expect(result.splicedBody.utf8.elementsEqual(source.utf8))
        #expect(result.customNodes.isEmpty)
        #expect(result.diagnostics.contains { $0.severity == .error })
        #expect(try render(result).contains("href=\"/target\""))
    }
}
