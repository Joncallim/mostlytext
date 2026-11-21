import Foundation

/// The result of a successful render (epic-20-implementation.md §6).
/// Width/height are the diagram's own natural size in points, taken from the
/// SVG's viewBox, so a display view can reserve correctly-proportioned
/// layout space before decoding the image.
///
/// Carries two representations of the same diagram, produced by one render
/// call: `svg` is Mermaid's own, unmodified vector markup — genuinely
/// resolution-independent — used for Export (spliced into HTML/PDF
/// untouched). `pngData` is a real WebKit-rendered raster snapshot of that
/// same SVG, used for native on-screen Preview display. Two
/// representations, not one, because a real Slice 4 spike proved AppKit's
/// own built-in SVG decoder (`NSImage`/`_NSSVGImageRep`) does not reliably
/// display real Mermaid output — it silently drops every `<foreignObject>`
/// label — so native, on-screen display needs a raster snapshot rendered by
/// the same engine that produced the diagram correctly in the first place,
/// mirroring `MathContribution`'s own PNG-based approach for the same
/// underlying reason (AppKit has no reliable way to display this content
/// as a resolution-independent vector on screen). `pngData` is `nil` only
/// when rasterization was deliberately skipped for static Quick Look or
/// failed for a reason unrelated to the diagram's own validity (see
/// `MermaidHarnessPage`); a genuinely invalid diagram
/// never reaches this type at all — `mermaid.render` itself throws first.
public struct RenderedMermaidDiagram: Sendable, Equatable {
    public let svg: String
    public let pngData: Data?
    public let naturalWidth: Double
    public let naturalHeight: Double

    public init(svg: String, pngData: Data?, naturalWidth: Double, naturalHeight: Double) {
        self.svg = svg
        self.pngData = pngData
        self.naturalWidth = naturalWidth
        self.naturalHeight = naturalHeight
    }
}
