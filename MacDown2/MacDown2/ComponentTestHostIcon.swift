import AppKit

/// Component-host window/tab tests do not qualify the product icon or the
/// machine's IconServices. Native UI-test launches keep the genuine icon.
@MainActor
enum ComponentTestHostIcon {
    static func installIfRequired(isTestHost: Bool, isUITesting: Bool, install: (NSImage) -> Void) {
        guard isTestHost, !isUITesting else { return }
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let pixels = bitmap.bitmapData else {
            preconditionFailure("The component test host could not allocate its icon fixture.")
        }
        pixels.initialize(repeating: 0x7F, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(bitmap)
        install(image)
    }
}
