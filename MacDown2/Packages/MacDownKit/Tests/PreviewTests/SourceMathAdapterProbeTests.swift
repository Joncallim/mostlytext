import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Textual

@MainActor
@Suite("Actual source-aware math attachment feasibility", .serialized)
struct SourceMathAdapterProbeTests {
    @Test(arguments: MathAdapterProbeSample.all)
    func sourceValuesAndLinksSurviveTheActualParser(_ sample: MathAdapterProbeSample) throws {
        let spans = try sample.spans()
        let references = try sample.references(for: spans)
        let result = MathAdapterProbe.parse(sample.source, spans: spans, references: references)
        try #require(!result.fellBack)
        let tags = result.text.runs.compactMap { $0[MathAdapterProbeSourceAttribute.self] }
        #expect(tags == spans)
        let attachments = result.text.runs.compactMap(\.textual.attachment)
        #expect(attachments.count == sample.count)
        #expect(Set(attachments).count == sample.count)
        if let expected = sample.expected {
            #expect(String(result.text.characters) == expected)
        }
        if sample.hasLink {
            try checkLinks(sample, result: result)
        }
        if sample.name == "emphasis" {
            #expect(result.text.runs.filter { $0.textual.attachment != nil }.allSatisfy {
                $0.inlinePresentationIntent?.contains(.emphasized) == true
            })
        }
        for (attachment, span) in zip(attachments, spans) {
            let delimiter = span.style == .inline ? "$" : "$$"
            #expect(attachment.description == delimiter + span.latex + delimiter)
            checkGeometry(attachment)
        }
    }

    @Test func nativeAttachmentMetricsAndParagraphConstruction() throws {
        let sample = MathAdapterProbeSample("paragraph", "Before $x$ after.")
        let result = try MathAdapterProbe.parse(sample.source, spans: sample.spans())
        try #require(!result.fellBack)
        #expect(String(result.text.characters) == "Before \u{FFFC} after.")
        let attachment = try #require(result.text.runs.compactMap(\.textual.attachment).first)
        let environment = TextEnvironmentValues()
        let metric = attachment.sizeThatFits(.unspecified, in: environment)
        #expect(metric.width.isFinite && metric.width > 0)
        #expect(metric.height.isFinite && metric.height > 0)
        #expect(attachment.baselineOffset(in: environment).isFinite)
        let builder = TextFragment<AttributedString>.TextBuilder(result.text, environment: environment)
        let host = NSHostingView(rootView: builder.text.frame(width: 400, alignment: .leading))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        #expect(size.width.isFinite && size.width > 0 && size.width <= 401)
        #expect(size.height.isFinite && size.height > 0)
    }

    @Test func factoryRetainsTheExistingAttachmentAndDistinctSourceOccurrences() throws {
        let parser = AttributedStringMarkdownParser(baseURL: nil, syntaxExtensions: [.math])
        let old = try parser.attributedString(for: "$x$")
        let attachment = try #require(old.runs.compactMap(\.textual.attachment).first)
        #expect(attachment == AnyAttachment.math(latex: "x", style: .inline))
        #expect(AnyAttachment.math(latex: "x", style: .inline, sourceID: UUID()) !=
            AnyAttachment.math(latex: "x", style: .inline, sourceID: UUID()))
    }

    @Test func collapsedReferenceControlDemonstratesTheOriginalLoss() throws {
        let sample = try #require(MathAdapterProbeSample.all.first { $0.name == "collapsed reference" })
        let spans = try sample.spans()
        let wrong = MathAdapterProbe.parse(sample.source, spans: spans)
        try #require(!wrong.fellBack)
        #expect(wrong.text.runs.allSatisfy { $0.link == nil })
        let corrected = try MathAdapterProbe.parse(
            sample.source,
            spans: spans,
            references: sample.references(for: spans)
        )
        try #require(!corrected.fellBack)
        #expect(corrected.text.runs.filter { $0.textual.attachment != nil }
            .allSatisfy { $0.link?.absoluteString == "/target" })
    }

    private func checkGeometry(_ attachment: AnyAttachment) {
        let environment = TextEnvironmentValues()
        let metric = attachment.sizeThatFits(.unspecified, in: environment)
        #expect(metric.width.isFinite && metric.width > 0)
        #expect(metric.height.isFinite && metric.height > 0)
        #expect(attachment.baselineOffset(in: environment).isFinite)
    }

    private func checkLinks(_ sample: MathAdapterProbeSample, result: MathAdapterProbe.Outcome) throws {
        let parser = AttributedStringMarkdownParser(baseURL: nil)
        let original = try parser.attributedString(for: sample.source)
        let targets = Set(original.runs.compactMap(\.link))
        #expect(!targets.isEmpty)
        #expect(Set(result.text.runs.compactMap(\.link)) == targets)
        #expect(result.text.runs.filter { $0.textual.attachment != nil }.allSatisfy {
            $0.link.map(targets.contains) == true
        })
        let spans = try sample.spans()
        let references = try sample.references(for: spans)
        let input = try MathAdapterProbe.rewrite(sample.source, spans: spans, references: references)
        if let definition = sample.source.range(of: "\n\n") {
            #expect(input.rewritten.hasSuffix(sample.source[definition.upperBound...]))
        }
    }
}
