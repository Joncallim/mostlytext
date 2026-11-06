import Contributions
import ExportService
import Foundation
import MarkdownEngine

@MainActor
extension ExportCoordinator {
    struct ContributionPreparation {
        let adaptation: ExportContributionAdapter.Adaptation
        let parser: FrozenExportParse
        let headings: HeadingAnchorPreparation?

        func request(from snapshot: OrdinaryExportSnapshot) -> ExportRequest {
            snapshot.request(contributions: adaptation.contributions, headingPreparation: headings)
        }
    }

    struct ExportOutcome {
        let primaryFile: URL
        let diagnostics: [ExportDiagnostic]
    }

    func performExport(
        snapshot: OrdinaryExportSnapshot,
        selection: ExportSelection,
        engine: any ParseExecuting = ParseEngine(),
        publicationLease: ExportLifetimeLease = ExportLifetimeLease(),
        admission: ExportDestinationAdmission? = nil
    ) async throws -> ExportOutcome {
        try publicationLease.checkActive()
        let openURLs = protectedExportDocumentURLs
        let authorization = try admission ?? ExportDestinationAdmission(
            capturing: selection.url, protecting: openURLs + (snapshot.documentURL.map { [$0] } ?? [])
        )
        try authorization.checkTarget(selection.url)
        try authorization.checkNoDocumentAliases(openURLs + (snapshot.documentURL.map { [$0] } ?? []))
        try authorization.checkNoFileAliases(
            protectedExportFileIdentities + (snapshot.protectedSourceIdentity.map { [$0] } ?? [])
        )
        let protection = documentProtections.register(authorization, lease: publicationLease)
        defer { documentProtections.remove(protection) }
        let preparation = try await exportContributionAdaptation(
            for: snapshot,
            isPrintTarget: selection.format == .pdf,
            engine: engine
        )
        try publicationLease.checkActive()
        let (adaptation, parser) = (preparation.adaptation, preparation.parser)
        let request = preparation.request(from: snapshot)

        switch selection.format {
        case .standaloneHTML, .selfContainedHTML:
            let mode: HTMLExportMode = selection.format == .selfContainedHTML
                ? .selfContained
                : .standalone(style: selection.style)
            let result = try await ExportService.exportHTML(
                request,
                to: .html(url: selection.url, mode: mode),
                engine: parser, lease: publicationLease, admission: authorization, recovery: recoveryLocation
            )
            return ExportOutcome(
                primaryFile: result.primaryFile,
                diagnostics: Self.combinedDiagnostics(adaptation, result.diagnostics)
            )
        case .pdf:
            let prepared = try await ExportService.prepare(
                request,
                target: .pdf(url: selection.url),
                engine: parser
            )
            try await PDFExportAdapter.export(
                prepared, to: selection.url, lease: publicationLease, admission: authorization
            )
            return ExportOutcome(
                primaryFile: selection.url,
                diagnostics: Self.combinedDiagnostics(adaptation, prepared.diagnostics)
            )
        }
    }

    /// Standalone (anchorless) diagnostics first, then the export service's
    /// own — the exact same order for both HTML and PDF, so the paths cannot
    /// drift through independently copy-pasted merge logic.
    nonisolated static func combinedDiagnostics(
        _ adaptation: ExportContributionAdapter.Adaptation,
        _ serviceDiagnostics: [ExportDiagnostic]
    ) -> [ExportDiagnostic] {
        adaptation.standaloneDiagnostics + serviceDiagnostics
    }

    /// Computes export-only contribution placements from the same frozen
    /// source and parse settings that the composer will use.
    private func exportContributionAdaptation(
        for snapshot: OrdinaryExportSnapshot,
        isPrintTarget: Bool,
        engine: any ParseExecuting
    ) async throws -> ContributionPreparation {
        let revision = Int(exactly: snapshot.sourceGeneration) ?? Int.max
        let parsed = try await engine.parse(
            snapshot.text,
            options: snapshot.parseOptions,
            revision: revision
        )
        let headings = try await Self.prepareHeadingTargets(snapshot: snapshot, document: parsed)
        let registry = ContributionRegistry.standardForExport(
            theme: snapshot.theme,
            isPrintTarget: isPrintTarget,
            headingIndex: headings?.index
        )
        let results = try await registry.run(
            document: parsed,
            sourceText: snapshot.text,
            sourceGeneration: snapshot.sourceGeneration
        )
        let adaptation = ExportContributionAdapter.adapt(
            results, destination: isPrintTarget ? .pdfExport : .htmlExport, requiringHeadingNavigation: headings != nil
        )
        if headings != nil, results.contains(where: { $0.contributionID == "toc" &&
                ($0.content == nil || $0.diagnostics.contains { $0.severity == .error })
        }) {
            throw ExportError.headingNavigationUnavailable
        }
        try adaptation.requirePublication()
        return ContributionPreparation(
            adaptation: adaptation,
            parser: FrozenExportParse(text: snapshot.text, revision: revision, document: parsed,
                                      options: snapshot.parseOptions, releaseAfterUse: true),
            headings: headings
        )
    }

    @concurrent
    private nonisolated static func prepareHeadingTargets(
        snapshot: OrdinaryExportSnapshot, document: MarkdownDocument
    ) async throws -> HeadingAnchorPreparation? {
        try Task.checkCancellation()
        guard TOCContribution.containsMarker(in: snapshot.text, document: document) else { return nil }
        do {
            return try await HeadingAnchorPreparation.prepare(
                document: document, sourceText: snapshot.text, documentID: snapshot.documentID,
                recoveryEpoch: snapshot.recoveryEpoch, sourceGeneration: snapshot.sourceGeneration
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ExportError.headingNavigationUnavailable
        }
    }
}
