import Foundation

// MARK: - Convert Case (EPIC-22 §6.13, Slice 4c-ii)

/// The three case-conversion transforms, matching Xcode's own "Convert
/// Case" submenu wording.
public enum TextCaseConversion {
    case uppercase
    case lowercase
    case capitalized
}

extension EditorTextTransforms {
    /// Requires every active selection to be real and non-empty (matching
    /// `applyMultiCursorInsert`'s own `allSatisfy` precedent, §6.13) — case
    /// conversion has no meaning for a bare caret, so a mix of a real
    /// selection and a bare caret declines the WHOLE command rather than
    /// silently converting only some of the active selections. No line-
    /// block merging is needed here (unlike Sort/Dedupe/Indent): a
    /// selection's own exact range is what gets rewritten, and
    /// `EditorSelectionSet.ranges` already guarantees non-overlapping,
    /// ascending-order ranges on its own.
    static func convertCaseTransaction(
        text: NSString,
        selection: EditorSelectionSet,
        conversion: TextCaseConversion
    ) -> EditorEditTransaction? {
        guard selection.ranges.allSatisfy({ $0.length > 0 }) else { return nil }

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for (index, range) in selection.ranges.enumerated() {
            let content = text.substring(with: range)
            let converted = convertedContent(content, conversion: conversion)
            replacements.append(TextReplacement(range: range, replacementText: converted))
            let newLength = (converted as NSString).length
            resultsByOriginalIndex[index] = NSRange(location: range.location + delta, length: newLength)
            delta += newLength - range.length
        }

        return EditorLineTransforms.makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: undoActionName(for: conversion)
        )
    }

    private static func convertedContent(_ content: String, conversion: TextCaseConversion) -> String {
        switch conversion {
        case .uppercase: content.uppercased()
        case .lowercase: content.lowercased()
        case .capitalized: content.capitalized
        }
    }

    private static func undoActionName(for conversion: TextCaseConversion) -> String {
        switch conversion {
        case .uppercase: String(localized: "Uppercase", bundle: .module)
        case .lowercase: String(localized: "Lowercase", bundle: .module)
        case .capitalized: String(localized: "Capitalize", bundle: .module)
        }
    }
}
