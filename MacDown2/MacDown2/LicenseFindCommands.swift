import SwiftUI

struct LicenseFindAction {
    let perform: @MainActor () -> Void
}

private struct LicenseFindActionKey: FocusedValueKey {
    typealias Value = LicenseFindAction
}

extension FocusedValues {
    var licenseFindAction: LicenseFindAction? {
        get { self[LicenseFindActionKey.self] }
        set { self[LicenseFindActionKey.self] = newValue }
    }
}

struct LicenseFindCommands: Commands {
    @FocusedValue(\.licenseFindAction) private var action

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find in Licenses…") { action?.perform() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(action == nil)
        }
    }
}
