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
