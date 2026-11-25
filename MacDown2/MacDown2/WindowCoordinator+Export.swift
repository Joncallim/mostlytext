import Foundation
import Workspace

enum ExportPhase: Equatable {
    case choosingDestination
    case preparing
    case exportingHTML
    case loadingPDF
    case printingPDF
    case validatingPDF
    case publishing
    case cancelling

    var label: String {
        label(locale: .current)
    }

    func label(locale: Locale, bundle: Bundle = .main) -> String {
        switch self {
        case .choosingDestination: String(localized: "Choosing export destination…", bundle: bundle, locale: locale)
        case .preparing: String(localized: "Preparing export…", bundle: bundle, locale: locale)
        case .exportingHTML: String(localized: "Exporting HTML…", bundle: bundle, locale: locale)
        case .loadingPDF: String(localized: "Loading PDF content…", bundle: bundle, locale: locale)
        case .printingPDF: String(
                localized: "Printing PDF (this step cannot be cancelled)…",
                bundle: bundle,
                locale: locale
            )
        case .validatingPDF: String(localized: "Checking PDF…", bundle: bundle, locale: locale)
        case .publishing: String(localized: "Saving export…", bundle: bundle, locale: locale)
        case .cancelling: String(localized: "Cancelling export…", bundle: bundle, locale: locale)
        }
    }

    var canRequestCancellation: Bool {
        self != .choosingDestination && self != .printingPDF && self != .publishing && self != .cancelling
    }
}

/// Tracks which documents currently have an export in flight. `ExportCoordinator`
/// is a stateless value type re-created per menu evaluation (see its own doc
/// comment), so this — the one piece of state an in-flight export actually
/// needs — lives on the coordinator, which persists across evaluations.
/// Scoped per `WorkspaceModel` (one per window) rather than app-wide, so
/// exporting two different documents in two different windows at the same
/// time is unaffected; only re-firing export for the *same* document while
/// its own export is still running is blocked.
extension WindowCoordinator {
    func isExporting(_ model: WorkspaceModel) -> Bool {
        exportingModels.contains(ObjectIdentifier(model))
    }

    func setExporting(_ isExporting: Bool, for model: WorkspaceModel) {
        let identifier = ObjectIdentifier(model)
        if isExporting {
            exportingModels.insert(identifier)
            exportPhases[identifier] = .choosingDestination
        } else {
            exportingModels.remove(identifier)
            exportPhases.removeValue(forKey: identifier)
            exportTasks.removeValue(forKey: identifier)
            exportLeases.removeValue(forKey: identifier)
        }
    }

    func exportPhase(for model: WorkspaceModel) -> ExportPhase? {
        exportPhases[ObjectIdentifier(model)]
    }

    func setExportPhase(_ phase: ExportPhase, for model: WorkspaceModel) {
        let identifier = ObjectIdentifier(model)
        guard exportingModels.contains(identifier),
              exportPhases[identifier] != .cancelling else { return }
        exportPhases[identifier] = phase
    }

    func cancelExport(for model: WorkspaceModel) {
        let identifier = ObjectIdentifier(model)
        guard let task = exportTasks[identifier],
              let phase = exportPhases[identifier], phase.canRequestCancellation else { return }
        exportPhases[identifier] = .cancelling
        exportLeases[identifier]?.revoke()
        task.cancel()
    }
}
