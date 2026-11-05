import Foundation
import SwiftUI
@_spi(Textual) import SwiftUIMath
import Testing

/// Exercises the actual locked dependency. Local acceptance uses a separate exact-source
/// Foundation fixture; these native metric assertions execute on the hosted runner.
@Suite("Math engine body inspection")
struct MathEngineInspectionTests {
    private let limits = SwiftUIMath.Math.BodyLimits(
        maximumUTF16Length: 16384, maximumDepth: 64, maximumParserSteps: 65536
    )

    @Test(arguments: ["\n", "\r\n", "\r"])
    func structuredErrorCursorIncludesOriginalComments(ending: String) throws {
        let body = "\\text{🙂}% ignored" + ending + #"\notARealCommand{x}"#
        guard case let .invalid(diagnostic) = try SwiftUIMath.Math.inspectBody(body, limits: limits) else {
            Issue.record("Expected the real engine's invalid-command diagnostic")
            return
        }
        #expect(diagnostic.error.code == .invalidCommand)
        #expect(diagnostic.utf16Offset == (body as NSString).range(of: "{x}", options: .literal).location)
        #expect(!diagnostic.error.message.isEmpty)
    }

    @Test func partialOptionalArgumentIsAnErrorWithoutCrashing() throws {
        guard case let .invalid(diagnostic) = try SwiftUIMath.Math.inspectBody(#"\cfrac["#, limits: limits) else {
            Issue.record("Expected an incomplete optional-argument diagnostic")
            return
        }
        #expect(diagnostic.error.code == .characterNotFound)
    }

    @Test func resourceExhaustionIsSeparateFromInvalidMath() throws {
        let bounded = SwiftUIMath.Math.BodyLimits(
            maximumUTF16Length: 128, maximumDepth: 4, maximumParserSteps: 64
        )
        guard case .resourceLimit(.depth) = try SwiftUIMath.Math.inspectBody("{{{{x}}}}", limits: bounded) else {
            Issue.record("Expected a depth limit rather than a malformed-math diagnostic")
            return
        }
    }

    @Test func commentCannotJoinTwoControlWordFragments() throws {
        guard case let .invalid(diagnostic) = try SwiftUIMath.Math.inspectBody("\\al%comment\npha", limits: limits)
        else {
            Issue.record("A comment must not manufacture an alpha command")
            return
        }
        #expect(diagnostic.error.code == .invalidCommand)
    }

    @Test func cancellationDoesNotBecomeAUserDiagnostic() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try SwiftUIMath.Math.inspectBody("{x", limits: limits)
                Issue.record("Cancelled inspection unexpectedly completed")
            } catch is CancellationError {
                // A cancelled generation must never publish a malformed-math diagnostic.
            } catch {
                Issue.record("Unexpected cancellation outcome: \(error)")
            }
        }
        await task.value
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func actualTypesetterOmitsCommentGlyphs(ending: String) {
        for (plain, commented) in [
            ("x+y", "x% ignored" + ending + "+y"),
            (#"\text{ab}"#, "\\text{a% ignored" + ending + "b}"),
        ] {
            let expected = bounds(plain)
            let actual = bounds(commented)
            #expect(expected.width > 0)
            #expect(actual.width == expected.width)
            #expect(actual.ascent == expected.ascent)
            #expect(actual.descent == expected.descent)
        }
    }

    private func bounds(_ body: String) -> SwiftUIMath.Math.TypographicBounds {
        SwiftUIMath.Math.typographicBounds(
            for: body, fitting: .unspecified,
            font: .init(name: .latinModern, size: 24), style: .text
        )
    }
}
