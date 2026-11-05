import Foundation

/// Bounds the complete Markdown input handed to the native Preview parser.
public enum PreviewParserBudget {
    public static let maximumUTF8Bytes = 64 * 1024
}
