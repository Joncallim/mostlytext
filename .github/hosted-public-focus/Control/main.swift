import AppKit
import Darwin

// Benign hosted control only. Construct no application in the owner account.
guard getuid() == geteuid(), getuid() > 0, let account = getpwuid(getuid()),
      String(cString: account.pointee.pw_name) == "runner",
      String(cString: account.pointee.pw_dir) == "/Users/runner",
      ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
else { exit(70) }

@MainActor
final class InputControl: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var count = 0
    private let counter = NSTextField(labelWithString: "0")

    func applicationDidFinishLaunching(_: Notification) {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "MostlyText hosted input control"
        let field = NSTextField(string: "")
        field.identifier = NSUserInterfaceItemIdentifier("positiveTextField")
        field.setAccessibilityIdentifier("positiveTextField")
        field.placeholderString = "Generated control input"
        field.frame = NSRect(x: 24, y: 110, width: 360, height: 24)
        let button = NSButton(title: "Increment", target: self, action: #selector(increment))
        button.setAccessibilityIdentifier("positiveButton")
        button.frame = NSRect(x: 24, y: 48, width: 150, height: 32)
        counter.setAccessibilityIdentifier("positiveCounter")
        counter.frame = NSRect(x: 210, y: 54, width: 120, height: 24)
        panel.contentView?.addSubview(field)
        panel.contentView?.addSubview(button)
        panel.contentView?.addSubview(counter)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
        NSApplication.shared.activate()
    }

    @objc private func increment() {
        count += 1
        counter.stringValue = String(count)
    }
}

let application = NSApplication.shared
let delegate = InputControl()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
