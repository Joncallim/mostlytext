import AppSettings
import SwiftUI

struct LegacyImportStartupView: View {
    let startup: LegacyImportStartup
    @State private var selected: Set<LegacyImportPlan.Destination> = []
    @State private var includeFont = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("MacDown Preferences").font(.title2)
                switch startup.phase {
                case .review:
                    Text(
                        LocalizedStringKey("Choose which original MacDown preferences to import. "
                            + "Your original preferences remain unchanged.")
                    )
                    if let review = startup.review {
                        LegacyMigrationPolicyNotes(source: review.source)
                        ForEach(review.plan.entries, id: \.destination) { entry in
                            Toggle(isOn: selection(entry.destination)) {
                                VStack(alignment: .leading) {
                                    Text(label(entry.destination))
                                    switch entry.disposition {
                                    case let .fillProvenAbsent(value), let .retainPersisted(_, value):
                                        Text(value ? LocalizedStringKey("Import value: On") :
                                            LocalizedStringKey("Import value: Off")).font(.caption)
                                    default: EmptyView()
                                    }
                                    Text(review.replacesSavedEditor ?
                                        LocalizedStringKey("Replace the saved MostlyText value.") :
                                        LocalizedStringKey("Import this value."))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let name = review.unavailableFontName {
                            Text("The original editor font cannot be reproduced exactly and will not be imported.")
                                .font(.caption)
                            Text(verbatim: name).font(.caption).foregroundStyle(.secondary)
                        }
                        if let font = review.font {
                            Toggle(isOn: $includeFont) {
                                VStack(alignment: .leading) {
                                    Text("Editor font")
                                    Text(verbatim: "\(font.postScriptName), \(font.descriptor.size) pt")
                                        .font(.caption)
                                    Text(review.replacesSavedEditor ?
                                        LocalizedStringKey("Replace the saved MostlyText value.") :
                                        LocalizedStringKey("Import this value."))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text(
                        LocalizedStringKey("Unavailable fonts, unsupported preferences and legacy themes "
                            + "are kept unchanged. "
                            + "MostlyText theme choices are preserved.")
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Continue Without Importing") { Task { await startup.continueWithoutImporting() } }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Import Selected Preferences") {
                            Task { await startup.apply(selected: selected, includeFont: includeFont) }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selected.isEmpty && !includeFont)
                    }
                case .blocked:
                    Text(
                        LocalizedStringKey("The import could not continue safely. "
                            + "Close the original MacDown if it is running. "
                            + "Existing preferences and recovery records have been preserved. "
                            + "You can continue without importing and review the import on a later launch.")
                    )
                    Button("Continue Without Importing") { Task { await startup.continueWithoutImporting() } }
                        .keyboardShortcut(.defaultAction)
                case .inspecting, .running:
                    ProgressView("Checking MacDown preferences…")
                case .ready:
                    EmptyView()
                }
            }
            .padding(24)
            .frame(width: 540)
        }
        .frame(width: 590, height: 540)
    }

    private func selection(_ destination: LegacyImportPlan.Destination) -> Binding<Bool> {
        Binding(get: { selected.contains(destination) }, set: { value in
            if value {
                selected.insert(destination)
            } else {
                selected.remove(destination)
            }
        })
    }

    private func label(_ destination: LegacyImportPlan.Destination) -> LocalizedStringKey {
        switch destination {
        case .smartHome: "Smart Home key"
        case .convertsTabsToSpaces: "Convert tabs to spaces"
        case .autoIncrementOrderedLists: "Automatically increment numbered lists"
        }
    }
}
