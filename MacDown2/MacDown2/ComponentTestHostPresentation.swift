import AppKit

/// Component-host window/tab tests do not qualify the product icon or the
/// machine's IconServices. Native UI-test launches keep the genuine icon.
@MainActor
enum ComponentTestHostPresentation {
    static var isCurrentComponentHost: Bool {
        isRequired(isTestHost: SingleTestInstanceGuard.isRunningUnderXCTest,
                   isUITesting: AppDelegate.launchArguments.contains("-UITesting"))
    }

    static func isRequired(isTestHost: Bool, isUITesting: Bool) -> Bool {
        isTestHost && !isUITesting
    }

    static func installIconIfRequired(isTestHost: Bool, isUITesting: Bool, install: (NSImage) -> Void) {
        guard isRequired(isTestHost: isTestHost, isUITesting: isUITesting) else { return }
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let pixels = bitmap.bitmapData else {
            preconditionFailure("The component test host could not allocate its icon fixture.")
        }
        for row in 0 ..< bitmap.pixelsHigh {
            for column in 0 ..< bitmap.pixelsWide {
                let offset = row * bitmap.bytesPerRow + column * 4
                for channel in 0 ..< 3 {
                    pixels[offset + channel] = column.isMultiple(of: 2) ? 0 : 0xFF
                }
                pixels[offset + 3] = 0xFF
            }
        }
        // Distinct opaque endpoints survive AppKit's image-representation and
        // color-space normalization, so readback proves the actual fixture.
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(bitmap)
        install(image)
    }
}
