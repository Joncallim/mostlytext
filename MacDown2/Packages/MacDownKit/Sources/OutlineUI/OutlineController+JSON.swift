import JSONSupport

// MARK: - JSON outline channel (EPIC-11 §3.4)

/// Format-neutral outline integration: the Markdown channel (`update(...)`)
/// and the JSON channel (`updateJSON(...)`) are independent; exactly one is
/// active for a document, and a format transition clears the other.
///
/// JSON outline contracts:
/// - IDs are key-path/array-index paths (`$.a.b[0]`), stable across edits
///   and formatting, so collapse/selection state survives rebuilds without
///   remapping.
/// - Duplicate-key documents are rejected by the parser before outline
///   construction, so no duplicate-key nodes or disambiguation rules exist.
/// - Invalid JSON publishes the parser's single diagnostic and no items;
///   the previous valid outline is NOT silently kept or cleared without an
///   explicit policy. Policy: the invalid state replaces the outline (the
///   sidebar shows the diagnostic), matching "invalid never clears a valid
///   outline without an explicit policy decision" — the decision here is
///   that the diagnostic is the outline's content for an invalid document.
public extension OutlineController {
    /// Rebuilds the JSON channel from an analysis result.
    ///
    /// No-ops when the text matches the last applied text AND the availability
    /// verdict is unchanged, so SwiftUI body evaluations are free.
    ///
    /// - Parameters:
    ///   - result: the session's latest `JSONAnalysisResult`, or `nil` when
    ///     the active document is not JSON (clears the channel).
    ///   - formatID: the active document's format id; only `"json"` populates.
    func updateJSON(result: JSONAnalysisResult?, formatID: String) {
        guard formatID == "json" else {
            clearJSONChannel()
            return
        }
        let newAvailability: OutlineAvailability = if let result {
            result.isValid ? .ready : .invalidJSON
        } else {
            .notParsed
        }
        let textMatches = switch (result?.text, lastAppliedJSONText) {
        case (nil, nil): true
        case let (.some(current), .some(previous)): current.utf8.elementsEqual(previous.utf8)
        default: false
        }
        guard !textMatches || newAvailability != jsonAvailability else {
            return
        }

        jsonItems = result?.outlineItems ?? []
        jsonAvailability = newAvailability
        jsonDiagnostic = result?.diagnostic
        lastAppliedJSONText = result?.text
        jsonRebuildCount += 1

        setJSONCurrentItemID(Self.resolveJSONCurrentItemID(
            offset: jsonReferenceOffset,
            items: jsonItems
        ))
    }

    /// Editor caret or viewport moved — a UTF-16 offset into the live text.
    /// The current JSON item is the deepest node whose source range contains
    /// the offset. Cheap enough to call on every keystroke and scroll tick.
    func jsonReferenceOffsetDidChange(_ utf16Offset: Int) {
        jsonReferenceOffset = utf16Offset
        setJSONCurrentItemID(Self.resolveJSONCurrentItemID(
            offset: utf16Offset,
            items: jsonItems
        ))
    }

    /// JSON outline row activated (click or Return). Publishes
    /// `pendingJSONJumpSourceRange` (UTF-16) and moves `jsonSelectedItemID`.
    func activateJSON(_ id: String) {
        guard let item = JSONOutlineBuilder.item(withID: id, in: jsonItems) else { return }
        pendingJSONJumpSourceRange = item.sourceRange
        jsonSelectedItemID = id
    }

    /// Moves keyboard focus onto the JSON outline, selecting a row when
    /// nothing is selected yet.
    func requestJSONFocus() {
        if jsonSelectedItemID == nil {
            jsonSelectedItemID = jsonCurrentItemID
                ?? JSONOutlineBuilder.visibleRows(jsonItems, collapsed: jsonCollapsedItemIDs).first?.id
        }
        jsonFocusRequestID += 1
    }

    /// Clears the JSON channel (format transition away from JSON, or a
    /// non-JSON document in this window).
    func clearJSONChannel() {
        guard !jsonItems.isEmpty || jsonAvailability != .notParsed || jsonDiagnostic != nil else {
            return
        }
        jsonItems = []
        jsonAvailability = .notParsed
        jsonDiagnostic = nil
        jsonCurrentItemID = nil
        jsonSelectedItemID = nil
        pendingJSONJumpSourceRange = nil
        lastAppliedJSONText = nil
        jsonRebuildCount += 1
    }

    /// Assigns `jsonCurrentItemID` only when it actually changes, so
    /// keystroke/scroll-tick callbacks do not re-render the sidebar.
    private func setJSONCurrentItemID(_ newValue: String?) {
        guard jsonCurrentItemID != newValue else { return }
        jsonCurrentItemID = newValue
    }

    /// The deepest JSON node whose source range contains `offset`, or `nil`.
    private static func resolveJSONCurrentItemID(
        offset: Int?,
        items: [ContentOutlineItem]
    ) -> String? {
        guard let offset else { return nil }
        return deepestContaining(items, offset: offset)?.id
    }

    private static func deepestContaining(
        _ items: [ContentOutlineItem],
        offset: Int
    ) -> ContentOutlineItem? {
        for item in items where item.sourceRange.contains(offset) {
            if let child = deepestContaining(item.children, offset: offset) {
                return child
            }
            return item
        }
        return nil
    }
}
