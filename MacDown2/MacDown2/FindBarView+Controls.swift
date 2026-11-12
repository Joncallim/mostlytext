import SwiftUI

extension FindBarView {
    var recentSearchMenu: some View {
        Menu {
            ForEach(recentQueries.indices, id: \.self) { index in
                Button {
                    model.query = recentQueries[index]
                    isQueryFocused = true
                } label: {
                    // A search term is authored text, never a localization key.
                    Text(verbatim: recentQueries[index])
                }
            }
            Divider()
            Button("Clear Search History") { onClearRecentQueries() }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .disabled(recentQueries.isEmpty)
        .help("Recent Searches")
        .accessibilityLabel("Recent Searches")
        .accessibilityIdentifier("findBarRecentSearches")
    }

    func optionToggle(_ title: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(minWidth: 20)
        }
        .buttonStyle(.bordered)
        .tint(isOn.wrappedValue ? Color.accentColor : Color.clear)
        .help(help)
    }
}
