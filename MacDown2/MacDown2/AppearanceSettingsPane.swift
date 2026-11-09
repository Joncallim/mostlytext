import SwiftUI
import Themes

struct AppearanceSettingsPane: View {
    @Environment(\.themeController) private var themeController

    var body: some View {
        if let themeController {
            AppearanceSettingsForm(controller: themeController)
        } else {
            ContentUnavailableView("Settings Unavailable", systemImage: "paintpalette")
        }
    }
}

private struct AppearanceSettingsForm: View {
    let controller: ThemeController
    @Environment(\.themeCatalog) private var themeCatalog
    @State private var selectedID = ""

    private var previewTheme: Theme {
        controller.available.first { $0.id == selectedID } ?? controller.current
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: Binding(
                    get: { controller.appearanceMode }, set: { controller.setAppearanceMode($0) }
                )) {
                    Text("Follow System").tag(ThemeAppearanceMode.system)
                    Text("Light").tag(ThemeAppearanceMode.light)
                    Text("Dark").tag(ThemeAppearanceMode.dark)
                }
                .accessibilityIdentifier("themeAppearanceMode")
                themePicker(.light)
                themePicker(.dark)
                Button("Reset Theme Choices") {
                    controller.resetThemeChoices()
                    selectedID = controller.current.id
                }
                .accessibilityIdentifier("resetThemeChoices")
            }
            .disabled(themeCatalog?.isBusy == true)
            if let themeCatalog {
                ThemeManagementSection(model: themeCatalog, controller: controller, selectedID: $selectedID)
            }
            Section("Theme Preview") {
                ThemePreviewSample(theme: previewTheme)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if selectedID.isEmpty {
                selectedID = controller.current.id
            }
        }
        .onChange(of: controller.current.id) { _, id in selectedID = id }
    }

    private func themePicker(_ appearance: ThemeAppearance) -> some View {
        Picker(appearance == .light ? String(localized: "Light Theme") : String(localized: "Dark Theme"),
               selection: Binding(
                   get: { appearance == .light ? controller.light.id : controller.dark.id },
                   set: { id in
                       selectedID = id
                       if appearance == .light {
                           controller.selectLight(id: id)
                       } else {
                           controller.selectDark(id: id)
                       }
                   }
               )) {
            ForEach(controller.available.filter { $0.appearance == appearance }) { theme in
                Text(verbatim: ThemePickerDisplayName.name(for: theme)).tag(theme.id)
            }
        }
        .accessibilityIdentifier(appearance == .light ? "lightThemePicker" : "darkThemePicker")
    }
}

/// A local value-only sample: choosing a theme never parses or edits a document.
private struct ThemePreviewSample: View {
    let theme: Theme
    private var palette: ResolvedPresentationPalette {
        ResolvedPresentationPalette(theme: theme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A place for your words")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .foregroundStyle(Color(nsColor: palette.heading.nsColor))
            HStack(spacing: 6) {
                Text("Prose and")
                Text("a link")
                    .underline()
                    .foregroundStyle(Color(nsColor: palette.link.nsColor))
                Text(verbatim: "`code`")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color(nsColor: palette.codeForeground.nsColor))
                    .background(Color(nsColor: palette.codeBackground.nsColor))
            }
            HStack(spacing: 8) {
                Rectangle().fill(Color(nsColor: palette.quoteBorder.nsColor)).frame(width: 3)
                Text("A quotation keeps its own voice.")
                    .foregroundStyle(Color(nsColor: palette.quoteForeground.nsColor))
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                code("let", capture: "keyword")
                code(" title = ", capture: "variable")
                code("\"MostlyText\"", capture: "string")
            }
            .font(.system(.body, design: .monospaced))
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: palette.codeBackground.nsColor))
            Text("Selected text")
                .foregroundStyle(Color(nsColor: palette.selectionForeground.nsColor))
                .padding(.horizontal, 3)
                .background(Color(nsColor: palette.selectionBackground.nsColor))
        }
        .foregroundStyle(Color(nsColor: palette.foreground.nsColor))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: palette.background.nsColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme Preview")
        .accessibilityIdentifier("themePreviewSample")
    }

    private func code(_ text: String, capture: String) -> some View {
        let style = theme.style(for: capture)
        return Text(verbatim: text)
            .foregroundStyle(Color(nsColor: (style?.color ?? palette.codeForeground).nsColor))
            .bold(style?.bold ?? false)
            .italic(style?.italic ?? false)
            .underline(style?.underline ?? false)
    }
}
