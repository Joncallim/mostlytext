import AppKit
import Foundation

// MARK: - Live text source

public extension EditorTextSystem {
    /// The live UTF-16-addressable text backing the editor, without
    /// materializing an additional whole-document Swift `String`.
    ///
    /// TextKit 2's `NSTextContentStorage` uses an `NSTextStorage` as its
    /// default backing store, so the common path returns the storage's
    /// `mutableString` directly. If that backing source is unavailable on the
    /// supported toolchain, the accessor fails open: `nil` means the assist
    /// adapter falls back to native AppKit behavior (never an O(document)
    /// copy).
    var assistTextSource: NSString? {
        if let storage = contentStorage.attributedString as? NSTextStorage {
            return storage.mutableString
        }
        return textView.textStorage?.mutableString
    }
}

// MARK: - Editing assist adapter

extension EditorTextSystem {
    /// Applies a pure-engine outcome through exactly one native `NSTextView`
    /// edit. Returns `true` when the input was handled by E10.
    ///
    /// - `.passthrough` → `false`; AppKit performs the original operation.
    /// - `.selection(range)` → clamped selection change, no undo entry.
    /// - `.handledNoChange` → `true`, nothing mutated.
    /// - `.edit(edit)` → one `insertText(_:replacementRange:)` wrapped in
    ///   `breakUndoCoalescing()` so it is one atomic undo step, with the
    ///   assist re-entrancy guard raised so the nested delegate callback
    ///   returns true without re-transforming.
    @discardableResult
    func applyAssistOutcome(_ outcome: EditingAssistOutcome) -> Bool {
        switch outcome {
        case .passthrough:
            return false
        case let .selection(range):
            textView.setSelectedRange(clampedAssistRange(range))
            return true
        case .handledNoChange:
            return true
        case let .edit(edit):
            // Guard the replacement range against the live text length. The
            // length comes from the local source seam — `textView.string`
            // would materialize a full-document Swift `String` copy on every
            // assist, violating the §2.4/§17.1 hot-path contract.
            let liveLength = liveSourceLength
            let location = min(max(0, edit.replacementRange.location), liveLength)
            let length = min(max(0, edit.replacementRange.length), liveLength - location)
            let range = NSRange(location: location, length: length)

            textView.breakUndoCoalescing()
            isPerformingEditingAssist = true
            defer { isPerformingEditingAssist = false }
            textView.insertText(edit.replacementString, replacementRange: range)
            textView.setSelectedRange(clampedAssistRange(edit.resultingSelection))
            if undoManager.canUndo {
                undoManager.setActionName(edit.undoActionName)
            }
            textView.breakUndoCoalescing()
            return true
        }
    }

    /// The live UTF-16 length from the local source seam, falling back to the
    /// text view's own storage; a full Swift `String` extraction is the last
    /// resort only (the seam is guaranteed on the supported toolchain).
    private var liveSourceLength: Int {
        (assistTextSource as NSString?)?.length
            ?? textView.textStorage?.mutableString.length
            ?? (textView.string as NSString).length
    }

    /// Clamps a range against the live source length without materializing
    /// a whole-document Swift `String`.
    private func clampedAssistRange(_ range: NSRange) -> NSRange {
        MarkdownEditingAssistEngine.clampedRange(range, length: liveSourceLength)
    }

    /// Applies a Markdown formatting command (Bold / Italic / Inline Code /
    /// Heading 1...6 / Paragraph) through the same one-edit adapter.
    ///
    /// Invalid heading levels are rejected at this entry boundary and never
    /// reach the pure engine.
    @discardableResult
    public func performMarkdownCommand(_ command: MarkdownEditingCommand) -> Bool {
        if case let .heading(level) = command, !(1 ... 6).contains(level) {
            return false
        }
        guard editingAssistConfiguration.isEnabled, editingAssistConfiguration.isMarkdownFormat else { return false }
        // Bold / Italic / Heading would rewrite marked (IME) text instead of failing open, like every other command.
        guard canApplyCommandEdit else { return false }
        guard let source = assistTextSource else { return false }
        if selectionSet.isMultiple {
            return applyMultiCursorMarkdownCommand(command, source: source)
        }
        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .markdownCommand(command),
            text: source,
            selection: selectedRange,
            configuration: editingAssistConfiguration,
            profile: languageEditingProfile
        )
        return applyAssistOutcome(outcome)
    }
}
