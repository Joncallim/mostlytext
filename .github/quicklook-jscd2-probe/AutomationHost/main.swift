import AppKit
import OSLog

// The UI-test machinery may instrument this private host, never the provider.
Logger(subsystem: "app.mostlytext.qlreplyprobe", category: "automation")
    .notice("QL_REPLY_PROBE separate-automation-host-started")
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
