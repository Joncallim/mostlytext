import Foundation

/// Exhaustive original-MacDown declarations, bound to the inspected source in
/// planning/downstream/legacy-preference-dispositions.json. Unsupported keys
/// remain visible in a local report; they never become no-op destination keys.
public enum LegacyPreferenceCatalog {
    public enum ValueKind: Sendable { case boolean, string, number, enumeration, font, opaque }
    public enum Policy: Sendable { case mapped, font, legacyTheme, capabilityPolicy, updateConsent, unconditional,
                                        provenance, unsupported, calculated,
                                        transient
    }

    public struct Definition: Sendable {
        public let key: String
        public let valueKind: ValueKind
        public let policy: Policy

        fileprivate init(_ key: String, _ valueKind: ValueKind, _ policy: Policy) {
            self.key = key
            self.valueKind = valueKind
            self.policy = policy
        }
    }

    public static let definitions: [Definition] = [
        .init("firstVersionInstalled", .string, .provenance),
        .init("latestVersionInstalled", .string, .provenance),
        .init("updateIncludesPreReleases", .boolean, .updateConsent),
        .init("supressesUntitledDocumentOnLaunch", .boolean, .unsupported),
        .init("createFileForLinkTarget", .boolean, .unsupported),
        .init("extensionIntraEmphasis", .boolean, .unsupported),
        .init("extensionTables", .boolean, .unconditional),
        .init("extensionFencedCode", .boolean, .unconditional),
        .init("extensionAutolink", .boolean, .unsupported),
        .init("extensionStrikethough", .boolean, .unconditional),
        .init("extensionUnderline", .boolean, .unsupported),
        .init("extensionSuperscript", .boolean, .unsupported),
        .init("extensionHighlight", .boolean, .unsupported),
        .init("extensionFootnotes", .boolean, .unsupported),
        .init("extensionQuote", .boolean, .unsupported),
        .init("extensionSmartyPants", .boolean, .unsupported),
        .init("markdownManualRender", .boolean, .unsupported),
        .init("editorBaseFontInfo", .font, .font),
        .init("editorAutoIncrementNumberedLists", .boolean, .mapped),
        .init("editorConvertTabs", .boolean, .mapped),
        .init("editorInsertPrefixInBlock", .boolean, .unsupported),
        .init("editorCompleteMatchingCharacters", .boolean, .unsupported),
        .init("editorSyncScrolling", .boolean, .unsupported),
        .init("editorSmartHome", .boolean, .mapped),
        .init("editorStyleName", .string, .legacyTheme),
        .init("editorHorizontalInset", .number, .unsupported),
        .init("editorVerticalInset", .number, .unsupported),
        .init("editorLineSpacing", .number, .unsupported),
        .init("editorWidthLimited", .boolean, .unsupported),
        .init("editorMaximumWidth", .number, .unsupported),
        .init("editorOnRight", .boolean, .unsupported),
        .init("editorShowWordCount", .boolean, .unsupported),
        .init("editorWordCountType", .enumeration, .unsupported),
        .init("editorScrollsPastEnd", .boolean, .unsupported),
        .init("editorEnsuresNewlineAtEndOfFile", .boolean, .unsupported),
        .init("editorUnorderedListMarkerType", .enumeration, .unsupported),
        .init("previewZoomRelativeToBaseFontSize", .boolean, .unsupported),
        .init("htmlTemplateName", .string, .unsupported),
        .init("htmlStyleName", .string, .unsupported),
        .init("htmlDetectFrontMatter", .boolean, .unsupported),
        .init("htmlTaskList", .boolean, .unconditional),
        .init("htmlHardWrap", .boolean, .unsupported),
        .init("htmlMathJax", .boolean, .capabilityPolicy),
        .init("htmlMathJaxInlineDollar", .boolean, .capabilityPolicy),
        .init("htmlSyntaxHighlighting", .boolean, .unsupported),
        .init("htmlHighlightingThemeName", .string, .unsupported),
        .init("htmlLineNumbers", .boolean, .unsupported),
        .init("htmlGraphviz", .boolean, .capabilityPolicy),
        .init("htmlMermaid", .boolean, .capabilityPolicy),
        .init("htmlCodeBlockAccessory", .enumeration, .unsupported),
        .init("htmlDefaultDirectoryUrl", .opaque, .unsupported),
        .init("htmlRendersTOC", .boolean, .capabilityPolicy),
        .init("editorBaseFontName", .string, .calculated),
        .init("editorBaseFontSize", .number, .calculated),
        .init("editorBaseFont", .opaque, .calculated),
        .init("editorUnorderedListMarker", .string, .calculated),
        .init("filesToOpen", .opaque, .transient),
        .init("pipedContentFileToOpen", .string, .transient),
    ]
}
