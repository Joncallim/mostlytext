import AppKit
import Contributions
import ExportService
import Foundation
import MarkdownEngine

/// Disabled #117 operation. Capturing and reserving happen synchronously at
/// command dispatch; no production command invokes this until the remaining
/// native and policy gates pass.
extension WindowCoordinator {
    /// Hidden entry point for the real sheet. It shares the capture and guard
    /// with the injected chooser below; no app command invokes it yet.
    func beginValidatedSVGExportUsingPanel() -> Task<ExportResult?, Error>? {
        guard let model = keyModel,
              let controller = controllers.first(where: { $0.model === model && !$0.isClosed })
        else { return nil }
        return beginValidatedSVGExportUsingPanel(from: controller)
    }

    /// Explicit origin and presentation hook keep the real AppKit sheet
    /// testable without relying on a headless host's key-window state.
    func beginValidatedSVGExportUsingPanel(
        from controller: WindowController,
        afterPresentation: (@MainActor (NSSavePanel) -> Void)? = nil
    ) -> Task<ExportResult?, Error>? {
        guard let document = controller.model.activeDocument else { return nil }
        let defaultName = document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        let directory = document.fileURL?.deletingLastPathComponent()
        return beginValidatedSVGExport(from: controller) { window in
            await ValidatedExportPanel.chooseTarget(
                in: window, defaultName: defaultName, directory: directory,
                afterPresentation: afterPresentation
            )
        }
    }

    func beginValidatedSVGExport(
        chooseTarget: @escaping @MainActor (NSWindow) async -> ExportTarget?,
        beforePublication: (@MainActor (ExportRequest) async -> Void)? = nil
    ) -> Task<ExportResult?, Error>? {
        guard let model = keyModel,
              let controller = controllers.first(where: { $0.model === model && !$0.isClosed })
        else { return nil }
        return beginValidatedSVGExport(
            from: controller, chooseTarget: chooseTarget, beforePublication: beforePublication
        )
    }

    /// Explicit-origin seam used by native tests, which have no reliable key
    /// window in a headless host. The command entry above supplies that origin.
    func beginValidatedSVGExport(
        from controller: WindowController,
        chooseTarget: @escaping @MainActor (NSWindow) async -> ExportTarget?,
        beforePublication: (@MainActor (ExportRequest) async -> Void)? = nil
    ) -> Task<ExportResult?, Error>? {
        let model = controller.model
        guard controllers.contains(where: { $0 === controller }), !controller.isClosed,
              !isExporting(model),
              let window = controller.window,
              let origin = controller.captureValidatedExportOrigin()
        else { return nil }
        setExporting(true, for: model)
        return Task { @MainActor in
            defer {
                origin.finish()
                setExporting(false, for: model)
            }
            try Task.checkCancellation()
            try origin.lease.checkActive()
            guard let target = await chooseTarget(window) else { return nil }
            try Task.checkCancellation()
            return try await Self.publishValidatedSVG(
                from: origin, to: target, beforePublication: beforePublication
            )
        }
    }

    private static func publishValidatedSVG(
        from origin: ValidatedExportOrigin, to target: ExportTarget,
        beforePublication: (@MainActor (ExportRequest) async -> Void)?
    ) async throws -> ExportResult {
        let frozen = try origin.freezeRequest()
        let revision = Int(exactly: frozen.sourceGeneration) ?? Int.max
        let parsed = try await ParseEngine().parse(frozen.text, revision: revision)
        try origin.lease.checkActive()
        let isPDF = switch target {
        case .pdf: true
        case .html: false
        }
        let registry = ContributionRegistry.standardForExport(
            theme: frozen.theme, isPrintTarget: isPDF
        )
        let results = try await registry.run(
            document: parsed, sourceText: frozen.text,
            sourceGeneration: frozen.sourceGeneration
        )
        try origin.lease.checkActive()
        let adaptation = ExportContributionAdapter.adapt(
            results, destination: isPDF ? .pdfExport : .htmlExport
        )
        try adaptation.requirePublication()
        let request = ExportRequest(
            text: frozen.text, sourceGeneration: frozen.sourceGeneration,
            theme: frozen.theme, documentURL: frozen.documentURL,
            resourceAccess: frozen.resourceAccess,
            protectedSourceIdentity: frozen.protectedSourceIdentity,
            contributions: adaptation.contributions
        )
        await beforePublication?(request)
        try origin.lease.checkActive()
        try Task.checkCancellation()
        let result = try await ExportService.exportValidatedSVG(
            request, to: target, lease: origin.lease,
            engine: FrozenExportParse(text: frozen.text, revision: revision, document: parsed)
        ) { validated, url, lease in
            try await PDFExportAdapter.export(validated, to: url, lease: lease)
        }
        return ExportResult(
            primaryFile: result.primaryFile, companionFiles: result.companionFiles,
            diagnostics: adaptation.standaloneDiagnostics + result.diagnostics
        )
    }
}
