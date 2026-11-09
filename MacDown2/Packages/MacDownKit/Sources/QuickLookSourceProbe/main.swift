import Darwin
import Foundation
import QuickLookSource

guard CommandLine.arguments.count == 2 else { exit(3) }
let file = URL(fileURLWithPath: CommandLine.arguments[1])
do {
    _ = try QuickLookSourceFallback.replyHTML(for: file)
    exit(1)
} catch QuickLookSourceError.notRegularFile {
    exit(0)
} catch {
    exit(2)
}
