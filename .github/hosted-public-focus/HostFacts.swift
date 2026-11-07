import AppKit
import Carbon
import CoreGraphics
import Darwin
import Foundation

@main
struct HostedGUIFacts {
    @MainActor
    static func main() throws {
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              FileManager.default.homeDirectoryForCurrentUser.path == "/Users/runner",
              getuid() == geteuid(), getuid() > 0,
              let account = getpwuid(getuid()), String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              (session[kCGSessionUserIDKey as String] as? NSNumber)?.uint32Value == getuid(),
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true,
              session["CGSSessionScreenIsLocked"] as? Bool != true,
              let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { throw Refusal.unavailable }
        let inputID = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        let screens = NSScreen.screens.map { screen in
            ["width": screen.frame.width, "height": screen.frame.height, "scale": screen.backingScaleFactor]
        }
        guard !inputID.isEmpty, !screens.isEmpty else { throw Refusal.unavailable }
        let result: [String: Any] = [
            "uid": getuid(), "on_console": true, "login_done": true,
            "screen_lock_field": session["CGSSessionScreenIsLocked"] ?? NSNull(),
            "keyboard_input_source": inputID, "screens": screens,
            "scope": "Actual hosted GUI metadata after positive input control, before ordinary product launch"
        ]
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: bytes, as: UTF8.self))
    }

    enum Refusal: Error { case unavailable }
}
