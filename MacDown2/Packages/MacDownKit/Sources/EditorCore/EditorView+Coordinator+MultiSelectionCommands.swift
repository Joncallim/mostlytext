import AppKit

extension EditorView.Coordinator {
    /// Routes multi-selection movement and directional deletion before the
    /// primary-only E10 command hook can consume one caret and discard the
    /// others. The caller already leaves marked-text commands to AppKit.
    @MainActor
    func handleMultiSelectionKeyboardCommand(_ selector: Selector, system: EditorTextSystem) -> Bool {
        if handleSynchronizedMovement(selector, system: system) {
            return true
        }
        guard system.selectionSet.isMultiple else { return false }
        return switch selector {
        case #selector(NSResponder.deleteBackward(_:)):
            system.applyMultiCursorDelete(.backward)
        case #selector(NSResponder.deleteForward(_:)):
            system.applyMultiCursorDelete(.forward)
        default:
            false
        }
    }
}
