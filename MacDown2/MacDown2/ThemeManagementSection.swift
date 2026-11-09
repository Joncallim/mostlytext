import SwiftUI
import Themes

struct ThemeManagementSection: View {
    let model: ThemeCatalogModel
    let controller: ThemeController
    @Binding var selectedID: String
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument: ThemeExportDocument?
    /// Share the document's catalogued fallback. A localized literal in this
    /// State initializer acquired a different file's location in Release extraction.
    @State private var exportName = ThemeExportDocument.suggestedName(String())

    private var selected: Theme {
        controller.available.first { $0.id == selectedID } ?? controller.current
    }

    private var custom: ThemeFile? {
        model.customThemes.first { $0.theme.id == selected.id }
    }

    var body: some View {
        Section("Manage Themes") {
            Picker("Theme", selection: $selectedID) {
                ForEach(controller.available) { theme in
                    Text(verbatim: ThemePickerDisplayName.name(for: theme)).tag(theme.id)
                }
            }
            .accessibilityIdentifier("managedThemePicker")
            if custom == nil {
                Text("Bundled with MostlyText").font(.callout)
            } else {
                Text("Custom theme stored in the Themes folder").font(.callout)
            }
            HStack {
                Button("Import…") { importing = true }
                    .accessibilityIdentifier("importTheme")
                Button("Duplicate") {
                    let snapshot = selected
                    Task { await model.duplicate(snapshot) }
                }
                .accessibilityIdentifier("duplicateTheme")
                Button("Export…") { prepareExport() }
                    .disabled(custom == nil)
                    .accessibilityIdentifier("exportTheme")
                Button("Delete…", role: .destructive) {
                    if let id = custom?.stableID {
                        Task { await model.prepareDeletion(id) }
                    }
                }
                .disabled(custom == nil)
                .accessibilityIdentifier("deleteTheme")
            }
            .disabled(!model.canManage)
            Button("Open Themes Folder") { Task { await model.revealDirectory() } }
                .accessibilityIdentifier("revealThemesFolder")
            if model.status == .loading {
                ProgressView("Loading themes…")
            }
            if model.state?.diagnostics.isEmpty == false {
                Text("Some custom themes could not be loaded. Their files were preserved.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if let problem = model.problem {
                Text(verbatim: problem).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("themeStorageProblem")
            }
            if custom != nil, ThemeReadability(theme: selected).hasLowContrastText {
                Text("This theme has low-contrast text. You can keep using it or choose another theme.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("themeContrastWarning")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [
            ThemeExportDocument.contentType,
            .json,
        ]) { result in
            switch result {
            case let .success(url): Task { await model.importTheme(from: url) }
            case let .failure(error): record(error)
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: ThemeExportDocument.contentType, defaultFilename: exportName) { result in
            if case let .failure(error) = result {
                record(error)
            }
        }
        .confirmationDialog("Replace the existing theme?", isPresented: Binding(
            get: { model.pendingImport != nil }, set: {
                if !$0 {
                    model.cancelPendingImport()
                }
            }
        ), titleVisibility: .visible) {
            Button("Replace Theme", role: .destructive) { model.resolvePendingImport(.replace) }
            Button("Import Copy") { model.resolvePendingImport(.importCopy) }
            Button("Cancel", role: .cancel) { model.cancelPendingImport() }
        } message: {
            Text("A different version of this theme is already installed. Replace it or import a separate copy.")
        }
        .confirmationDialog("Delete this custom theme?", isPresented: Binding(
            get: { model.pendingDeletion != nil }, set: {
                if !$0 {
                    model.cancelPendingDeletion()
                }
            }
        ), titleVisibility: .visible) {
            Button("Delete Theme", role: .destructive) { model.confirmDeletion() }
            Button("Cancel", role: .cancel) { model.cancelPendingDeletion() }
        } message: {
            Text("If this theme is selected, its appearance will return to a bundled theme.")
        }
        .onChange(of: model.operationID) { _, _ in selectedID = model.affectedThemeID ?? controller.current.id }
    }

    private func prepareExport() {
        guard let custom else { return }
        do {
            exportDocument = try ThemeExportDocument(theme: custom)
            exportName = ThemeExportDocument.suggestedName(custom.displayName)
            exporting = true
        } catch { record(error) }
    }

    private func record(_ error: Error) {
        let native = error as NSError
        guard native.domain != NSCocoaErrorDomain || native.code != NSUserCancelledError else { return }
        model.problem = ThemeCatalogModel.message(for: error)
    }
}
