import Foundation
import MarkdownEngine

/// The contributions MacDown 2 knows about, and the runner that executes
/// them. A plain `Sendable` value over a static array — like
/// `FileFormatRegistry`, not `GrammarRegistry` — because a contribution is
/// a cheap Swift value/struct instance, not a compiled artifact that needs
/// a lazy-build cache (epic-14-implementation.md §2.1).
public struct ContributionRegistry: Sendable {
    public let contributions: [any Contributing]
    private let locale: Locale

    public init(contributions: [any Contributing], locale: Locale = .current) {
        self.contributions = contributions
        self.locale = locale
    }

    /// The first-party contributions MacDown 2 ships.
    public static let standard = ContributionRegistry(contributions: [TOCContribution()])

    public static func standard(locale: Locale) -> ContributionRegistry {
        ContributionRegistry(contributions: [TOCContribution(locale: locale)], locale: locale)
    }

    /// Runs every registered contribution against one document snapshot
    /// and aggregates their results.
    ///
    /// Isolation: one contribution throwing does not prevent the rest from
    /// running. Its failure is recorded as a `content: nil` result carrying
    /// an `.error` diagnostic rather than propagating and silently
    /// dropping every other contribution's work. Cancellation is the one
    /// exception — a thrown `CancellationError` (from a contribution, or
    /// observed at the top of each iteration) abandons the remaining
    /// contributions and propagates out of this call immediately, matching
    /// Swift's own structured-concurrency convention that cancellation is
    /// not "one more failure to report."
    public func run(
        document: MarkdownDocument,
        sourceText: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult] {
        var results: [ContributionResult] = []
        for contribution in contributions {
            try Task.checkCancellation()
            do {
                let contributed = try await contribution.run(
                    document: document,
                    sourceText: sourceText,
                    sourceGeneration: sourceGeneration
                )
                try Task.checkCancellation()
                results.append(contentsOf: contributed)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let diagnostic = ContributionDiagnostic(
                    severity: .error,
                    message: String(
                        localized: "\(contribution.id) failed: \(error.localizedDescription)",
                        bundle: ContributionLocalization.bundle(for: locale), locale: locale
                    )
                )
                results.append(ContributionResult(
                    contributionID: contribution.id,
                    content: nil,
                    sourceGeneration: sourceGeneration,
                    diagnostics: [diagnostic]
                ))
            }
        }
        try Task.checkCancellation()
        return results
    }
}

enum ContributionLocalization {
    static func bundle(for locale: Locale) -> Bundle {
        let source = Bundle.module
        let preferred = Bundle.preferredLocalizations(from: source.localizations, forPreferences: [locale.identifier])
        guard let language = preferred.first,
              let url = source.url(forResource: language, withExtension: "lproj"),
              let selected = Bundle(url: url) else { return source }
        return selected
    }
}
