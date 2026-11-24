import AppKit
@testable import MacDown2
import Testing

/// Return (Rename) and ⌘D (Duplicate) must not be claimed by the Folder commands while a
/// text control — whose field editor is an `NSText` — is being edited.
@MainActor
struct FolderCommandTextFieldFocusTests {
    @Test func aFieldEditorIsATextEditingResponder() {
        #expect(WindowCoordinator.isTextEditing(NSTextView()))
    }

    @Test func otherResponderKindsAreNot() {
        #expect(!WindowCoordinator.isTextEditing(NSView()))
        #expect(!WindowCoordinator.isTextEditing(NSOutlineView()))
        #expect(!WindowCoordinator.isTextEditing(nil))
    }
}
