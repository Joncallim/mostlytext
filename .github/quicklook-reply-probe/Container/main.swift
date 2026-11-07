import AppKit
import OSLog

// The hosted cold-Finder probe must never launch this containing fixture.
Logger(subsystem: "app.mostlytext.qlreplyprobe", category: "container")
    .error("QL_REPLY_PROBE container-launched-invalidates-cold-proof")
exit(70)
