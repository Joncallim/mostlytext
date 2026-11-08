/// Scrollbar chrome must not reduce the width of an offscreen PDF canvas.
/// This policy is composed before validation; HTML exports retain their scrollbars.
enum PDFCanvasStylesheet {
    static let css = "html { scrollbar-width: none !important; }"
}
