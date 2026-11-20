import Foundation
import Testing
@testable import TextSearch

/// #183 F08 — a cancelled search must stop doing work (a pathological regex
/// backtracks for a very long time) and must never look like a complete result.
@Suite("Regex search cancellation (#183 F08)")
struct RegexCancellationTests {
    private static let pathologicalText = String(repeating: "x", count: 40) + "!"
    /// `(x+x+)+y` against "xxxx…!" backtracks exponentially (measured: still
    /// running after 3 s with ~25k ICU progress callbacks).
    private static let pathologicalOptions = SearchOptions(isRegex: true)

    @Test func aCancelledPathologicalRegexStopsPromptlyAndReportsCancellation() async throws {
        let task = Task.detached { () -> Result<[SearchMatch], SearchQueryError> in
            do {
                return try .success(TextSearchEngine.matches(
                    in: Self.pathologicalText,
                    query: "(x+x+)+y",
                    options: Self.pathologicalOptions
                ))
            } catch let error as SearchQueryError {
                return .failure(error)
            } catch {
                return .failure(.invalidRegex("\(error)"))
            }
        }
        try await Task.sleep(for: .milliseconds(150))
        let start = ContinuousClock.now

        task.cancel()
        let result = await task.value

        #expect(ContinuousClock.now - start < .seconds(5), "cancellation must stop the backtracking")
        guard case .failure(.cancelled) = result else {
            Issue.record("expected .cancelled, got \(result)")
            return
        }
    }

    @Test func anOrdinaryRegexIsUnaffected() throws {
        let matches = try TextSearchEngine.matches(
            in: "cat dog cat",
            query: "c.t",
            options: SearchOptions(isRegex: true)
        )
        #expect(matches.map(\.range.location) == [0, 8])
    }

    @Test func aNonCancelledPathologicalRegexTimesOutWithoutPublishingPartialMatches() {
        let start = ContinuousClock.now
        do {
            let result = try TextSearchEngine.matches(
                in: Self.pathologicalText, query: "(x+x+)+y", options: Self.pathologicalOptions
            )
            Issue.record("expected timeout, got \(result.count) complete matches")
        } catch {
            #expect(error == .timedOut)
        }
        #expect(ContinuousClock.now - start < .seconds(5), "ICU progress must bound backtracking")
    }

    @Test func aSearchThatIsAlreadyCancelledNeverReportsPartialResults() async {
        let task = Task.detached { () -> Result<[SearchMatch], SearchQueryError> in
            while !Task.isCancelled {
                await Task.yield()
            }
            do {
                return try .success(TextSearchEngine.matches(
                    in: "aaa",
                    query: "a",
                    options: SearchOptions(isRegex: true)
                ))
            } catch let error as SearchQueryError {
                return .failure(error)
            } catch {
                return .failure(.invalidRegex("\(error)"))
            }
        }
        task.cancel()

        let result = await task.value

        guard case .failure(.cancelled) = result else {
            Issue.record("expected .cancelled, got \(result)")
            return
        }
    }
}
