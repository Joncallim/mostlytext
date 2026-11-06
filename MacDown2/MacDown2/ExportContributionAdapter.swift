import Contributions
import ExportService

/// Turns contribution results into `ExportDerivedContribution`, the type
/// E12's already-built `DerivedContentComposer` consumes
/// (epic-14-implementation.md §6.6, §7.1). A standalone type, not an
/// extension on `ExportCoordinator`, so it stays trivially unit-testable
/// without constructing a real coordinator.
enum ExportContributionAdapter {
    /// The result of adapting one contribution run for Export: anchored
    /// contributions `DerivedContentComposer` can place, plus diagnostics
    /// from results that had nothing to anchor to at all (architecture
    /// takeover, pass 9/10). Kept separate from `ExportDerivedContribution`
    /// rather than widening E12's public type — a diagnostic-only result has
    /// no `sourceRange` to attach one to.
    struct Adaptation {
        let contributions: [ExportDerivedContribution]
        let standaloneDiagnostics: [ExportDiagnostic]

        /// Refuse before resource preparation or output publication, including
        /// fatal observations attached to content that will not be admitted.
        func requirePublication() throws {
            let fatal = (standaloneDiagnostics + contributions.flatMap(\.diagnostics)).filter(\.preventsPublication)
            guard fatal.isEmpty else { throw ExportError.derivedContentUnavailable(fatal) }
        }
    }

    /// Renders each placeable result's `.markdown` representation via
    /// `ExportService.renderMarkdownFragment`. `.html` is passed through
    /// verbatim as `ExportDerivedContribution.html` — `MathContribution`
    /// (E19, `Math` target) is the first producer of this case, and its
    /// fragment is already a self-contained `<img src="data:...">` string,
    /// so there is nothing further to render (epic-19-implementation.md
    /// §6.2). The switch below has no `default:` case, so a third
    /// `ContributionRepresentation` case fails to compile here until this
    /// adapter is updated to decide what it means.
    ///
    /// A `content == nil` result (nothing to do, or a registry-caught
    /// thrown failure, §6.1) carries no `sourceRange` to anchor to, so its
    /// diagnostics — if any — become `standaloneDiagnostics` instead of
    /// being dropped. A designed failure — a contribution that anchored
    /// real content but reported an `.error` diagnostic on it — stays
    /// attached to that contribution, since that result keeps its content
    /// and `DerivedContentComposer` already fails it closed.
    static func adapt(
        _ results: [ContributionResult],
        destination: ContributionDestination,
        requiringHeadingNavigation: Bool = false
    ) -> Adaptation {
        var contributions: [ExportDerivedContribution] = []
        var standaloneDiagnostics: [ExportDiagnostic] = []
        for result in results {
            guard let content = result.content else {
                standaloneDiagnostics.append(contentsOf: result.diagnostics.map(exportDiagnostic))
                continue
            }

            guard case .accepted = content.representation.admission(to: destination) else {
                standaloneDiagnostics.append(contentsOf: result.diagnostics.map(exportDiagnostic))
                standaloneDiagnostics.append(ExportDiagnostic(
                    severity: .error,
                    message: String(
                        localized: "\(result.contributionID) is unavailable for this export; authored source preserved"
                    )
                ))
                continue
            }

            let html: String
            let diagnostics = result.diagnostics.map(exportDiagnostic)
            switch content.representation {
            case let .markdown(markdown):
                html = ExportService.renderMarkdownFragment(markdown)
            case let .html(fragment):
                html = fragment
            }

            contributions.append(ExportDerivedContribution(
                sourceRange: content.sourceRange,
                placement: exportPlacement(for: content.placement),
                html: html,
                sourceGeneration: result.sourceGeneration,
                diagnostics: diagnostics,
                requiresHeadingNavigation: requiringHeadingNavigation && result.contributionID == "toc"
            ))
        }
        return Adaptation(contributions: contributions, standaloneDiagnostics: standaloneDiagnostics)
    }

    private static func exportPlacement(for placement: ContributionPlacement) -> ExportDerivedPlacement {
        switch placement {
        case .inline: .inline
        case .block: .block
        }
    }

    private static func exportDiagnostic(_ diagnostic: ContributionDiagnostic) -> ExportDiagnostic {
        let severity: ExportDiagnostic.Severity = switch diagnostic.severity {
        case .warning: .warning
        case .error: .error
        }
        return ExportDiagnostic(severity: severity, message: diagnostic.message,
                                sourceRange: diagnostic.sourceRange, sourceID: diagnostic.sourceID,
                                sourceOffset: diagnostic.sourceOffset, code: diagnostic.code,
                                preventsPublication: diagnostic.preventsPublication)
    }
}
