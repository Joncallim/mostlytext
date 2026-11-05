import AppKit
import Foundation
import SwiftUI
@_spi(Textual) import SwiftUIMath
import Testing
@testable import Textual

@MainActor
@Suite("Validated raw-body native rendering", .serialized)
struct ValidatedBodyRenderingTests {
    private let limits = SwiftUIMath.Math.BodyLimits(
        maximumUTF16Length: 16384, maximumDepth: 64, maximumParserSteps: 65536
    )
    private let font = SwiftUIMath.Math.Font(name: .latinModern, size: 24)

    @Test(arguments: [false, true])
    func automaticAndRawBodyCachesKeepTheirOwnMeaning(rawFirst: Bool) throws {
        let expression = rawFirst ? #"\sum_{i=0}^{3}i"# : #"\sum_{i=0}^{4}i"#
        let wrapped = "$" + expression + "$"
        let admitted = try body(wrapped)
        let expectedRaw = bounds(expression, style: .display)
        let expectedAutomatic = bounds(expression, style: .text)
        #expect(expectedRaw.ascent + expectedRaw.descent > expectedAutomatic.ascent + expectedAutomatic.descent)
        let raw: SwiftUIMath.Math.TypographicBounds
        let automatic: SwiftUIMath.Math.TypographicBounds
        if rawFirst {
            raw = bounds(admitted, style: .display)
            automatic = bounds(wrapped, style: .display)
        } else {
            automatic = bounds(wrapped, style: .display)
            raw = bounds(admitted, style: .display)
        }
        check(raw, equals: expectedRaw)
        check(automatic, equals: expectedAutomatic)
        // Repeat both paths after cache warming and measured-width alias insertion.
        check(bounds(admitted, style: .display), equals: expectedRaw)
        check(bounds(wrapped, style: .display), equals: expectedAutomatic)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func typedAttachmentKeepsAuthoredSourceAndDistinctOccurrences(ending: String) throws {
        let source = "x% ignored🙂" + ending + "+y"
        let admitted = try body(source)
        let firstID = UUID(), secondID = UUID()
        let first = AnyAttachment.math(body: admitted, style: .inline, sourceID: firstID)
        let repeated = AnyAttachment.math(body: admitted, style: .inline, sourceID: firstID)
        let second = AnyAttachment.math(body: admitted, style: .inline, sourceID: secondID)
        #expect(first == repeated)
        #expect(first != second)
        #expect(Array(admitted.source.utf8) == Array(source.utf8))
        #expect(first.description == "$" + source + "$")
        let environment = TextEnvironmentValues()
        let expected = AnyAttachment.math(latex: "x+y", style: .inline)
        #expect(first.sizeThatFits(.unspecified, in: environment) ==
            expected.sizeThatFits(.unspecified, in: environment))
        #expect(first.baselineOffset(in: environment) == expected.baselineOffset(in: environment))
    }

    @Test func actualViewProducesAnImageFromTheAdmittedBody() throws {
        let admitted = try body("\\frac{x}{y}% ignored\r\n+z")
        let measured = bounds(admitted, style: .display)
        #expect(measured.width > 0 && measured.ascent + measured.descent > 0)
        let view = SwiftUIMath.Math(admitted)
            .mathFont(font)
            .mathTypesettingStyle(.display)
            .foregroundStyle(.black)
            .frame(width: measured.width, height: measured.ascent + measured.descent)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width > 0 && image.height > 0)
    }

    @Test func cancelledBodyDoesNotReuseAnAlreadyCachedDisplay() async throws {
        let admitted = try body("x+y+z")
        #expect(bounds(admitted, style: .text).width > 0)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let cancelled = bounds(admitted, style: .text)
            #expect(cancelled.width == 0)
            #expect(cancelled.ascent == 0)
            #expect(cancelled.descent == 0)
        }
        await task.value
    }

    @Test func typedBodyAttachmentAlsoRetainsDisplayPlacement() throws {
        let admitted = try body(#"\sqrt{x^2+y^2}"#)
        let attachment = AnyAttachment.math(body: admitted, style: .display, sourceID: UUID())
        #expect(attachment.description == "$$" + admitted.source + "$$")
        let environment = TextEnvironmentValues()
        let expected = AnyAttachment.math(latex: admitted.source, style: .display)
        #expect(attachment.sizeThatFits(.unspecified, in: environment) ==
            expected.sizeThatFits(.unspecified, in: environment))
    }

    private func body(_ source: String) throws -> SwiftUIMath.Math.ValidatedBody {
        let result = try SwiftUIMath.Math.validateBody(source, limits: limits)
        guard case let .valid(value) = result else {
            Issue.record("Expected admitted body")
            throw SwiftUIMath.Math.BodyConfigurationError.invalidLimits
        }
        return value
    }

    private func bounds(
        _ source: String, style: SwiftUIMath.Math.TypesettingStyle
    ) -> SwiftUIMath.Math.TypographicBounds {
        SwiftUIMath.Math.typographicBounds(for: source, fitting: .unspecified, font: font, style: style)
    }

    private func bounds(
        _ body: SwiftUIMath.Math.ValidatedBody, style: SwiftUIMath.Math.TypesettingStyle
    ) -> SwiftUIMath.Math.TypographicBounds {
        SwiftUIMath.Math.typographicBounds(for: body, fitting: .unspecified, font: font, style: style)
    }

    private func check(
        _ actual: SwiftUIMath.Math.TypographicBounds, equals expected: SwiftUIMath.Math.TypographicBounds
    ) {
        #expect(actual.width == expected.width)
        #expect(actual.ascent == expected.ascent)
        #expect(actual.descent == expected.descent)
    }
}
