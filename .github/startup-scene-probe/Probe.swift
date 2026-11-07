import AppKit
import Darwin
import SwiftUI

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var ready = false
    private var ownedWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        guard getuid() == geteuid(), getuid() != 0,
              let account = getpwuid(getuid()),
              String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              CommandLine.arguments.count == 2,
              CommandLine.arguments[1].hasPrefix("/Users/runner/work/_temp/mostlytext-scene/")
        else { exit(77) }
        Task { @MainActor in
            // Model the real asynchronous import completion, not a ready-at-init delegate.
            try? await Task.sleep(for: .milliseconds(150))
            let before = menuTitles()
            ready = true
            // The production coordinator owns AppKit windows; close only our placeholders.
            for window in NSApp.windows { window.close() }
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 240),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Standalone startup observation control"
            window.contentView = NSTextField(labelWithString: "Private harmless generated control")
            ownedWindow = window
            window.makeKeyAndOrderFront(nil)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            var samples: [[String]] = []
            while ContinuousClock.now < deadline {
                samples.append(menuTitles())
                try? await Task.sleep(for: .milliseconds(50))
            }
            let result: [String: Any] = ["ready": ready, "before": before, "samples": samples,
                                        "marker_seen": samples.contains { $0.contains("SCENE_READY_CONTROL") },
                                        "pid": ProcessInfo.processInfo.processIdentifier,
                                        "uid": getuid(), "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                        "scope": "Structural delayed-readiness control, not root-product acceptance"]
            do {
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
                NSApp.terminate(nil)
            } catch { exit(78) }
        }
    }

    private func menuTitles() -> [String] {
        func all(_ menu: NSMenu) -> [String] {
            menu.items.flatMap { [$0.title] + ($0.submenu.map(all) ?? []) }
        }
        return NSApp.mainMenu.map(all) ?? []
    }
}

@main
struct ProbeApp: App {
    @NSApplicationDelegateAdaptor(ProbeDelegate.self) private var delegate

    var body: some Scene {
        #if OBSERVED_SCENE
        ObservedProbeScene(delegate: delegate)
        #else
        let ready = delegate.ready
        WindowGroup { EmptyView() }
            .commands {
                if ready {
                    CommandMenu("SCENE_READY_CONTROL") { Button("Known control") {} }
                }
            }
        #endif
    }
}

struct ObservedProbeScene: Scene {
    @ObservedObject var delegate: ProbeDelegate
    var body: some Scene {
        let ready = delegate.ready
        WindowGroup { EmptyView() }
            .commands {
                if ready {
                    CommandMenu("SCENE_READY_CONTROL") { Button("Known control") {} }
                }
            }
    }
}
