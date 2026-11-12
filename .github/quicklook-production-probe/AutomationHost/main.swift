import AppKit

// UI automation belongs to this disposable host, never the product provider.
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
