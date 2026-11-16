/// The authored fence limit is checked before acquiring a WebKit page. The
/// generated SVG has a separate output limit after the renderer runs.
public enum DiagramSourceBudget {
    public static let maximumUTF8Bytes = 64 * 1024

    public static func byteCountIfOversized(_ source: String) -> Int? {
        let byteCount = source.utf8.count
        return byteCount > maximumUTF8Bytes ? byteCount : nil
    }
}
