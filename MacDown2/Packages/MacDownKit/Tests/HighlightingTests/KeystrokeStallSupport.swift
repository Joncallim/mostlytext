import AppKit
import Darwin
import EditorCore
import Foundation
@testable import Highlighting
import Testing
import Themes

/// Measures how long the main thread is unavailable, from a background thread.
///
/// A helper thread repeatedly posts a tiny block to the main queue and records
/// how long it waited to run. A block posted just before a long main-thread job
/// runs only after that job finishes, so the recorded latency is the length of
/// the stall the user would have felt (an event arriving then would have waited
/// as long). Everything that runs on the main thread is covered: the edit
/// itself, Neon's deferred invalidation, and any later highlight application.
final class MainThreadStallMonitor: @unchecked Sendable {
    struct Sample {
        let posted: UInt64
        let ran: UInt64
        var latencyNanoseconds: UInt64 {
            ran - posted
        }
    }

    private let lock = NSLock()
    private var samples: [Sample] = []
    private var running = false

    func start() {
        lock.withLock { running = true }
        let thread = Thread { [self] in
            while lock.withLock({ running }) {
                let semaphore = DispatchSemaphore(value: 0)
                let posted = DispatchTime.now().uptimeNanoseconds
                DispatchQueue.main.async {
                    let ran = DispatchTime.now().uptimeNanoseconds
                    self.lock.withLock { self.samples.append(Sample(posted: posted, ran: ran)) }
                    semaphore.signal()
                }
                semaphore.wait()
                usleep(500)
            }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        lock.withLock { running = false }
    }

    /// The longest main-thread stall whose end fell in `[start, end)`.
    func maxStall(endingIn start: UInt64, _ end: UInt64) -> Double {
        let latest = lock.withLock {
            samples.filter { $0.ran >= start && $0.ran < end }.map(\.latencyNanoseconds).max()
        }
        return Double(latest ?? 0) / 1e6
    }
}

/// CPU time consumed by the calling thread, in milliseconds. Unlike wall-clock
/// time it does not grow when the machine is loaded and the thread is preempted.
func currentThreadCPUMilliseconds() -> Double {
    var info = thread_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
    let port = mach_thread_self()
    defer { mach_port_deallocate(mach_task_self_, port) }
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    let user = Double(info.user_time.seconds) * 1000 + Double(info.user_time.microseconds) / 1000
    let system = Double(info.system_time.seconds) * 1000 + Double(info.system_time.microseconds) / 1000
    return user + system
}

/// Summary statistics over per-edit measurements, in milliseconds.
struct StallStats: CustomStringConvertible {
    let values: [Double]

    var max: Double {
        values.max() ?? 0
    }

    var p95: Double {
        percentile(0.95)
    }

    var median: Double {
        percentile(0.5)
    }

    private func percentile(_ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded(.up))
        return sorted[index]
    }

    var description: String {
        String(format: "max %.1f ms, p95 %.1f ms, median %.1f ms (n=%d)", max, p95, median, values.count)
    }
}

/// A Markdown fixture with headings, inline markup, lists, quotes and fences,
/// so both the block grammar and the inline injection are exercised.
enum StallFixtures {
    static let block = """
    # Heading with `code`

    Some *emphasis*, **strong** text and a [link](https://example.com) here.

    - list item one with `inline`
    - list item two

    > a quote with **bold**

    ```
    fenced code line
    ```


    """

    static func markdown(utf8Bytes: Int) -> String {
        Fixtures.markdownRepeating(line: block, totalBytes: utf8Bytes)
    }
}

/// One editor + Markdown highlighter, as the app wires them.
@MainActor
final class HighlightedEditor {
    let system: EditorTextSystem
    let highlighter: NeonSyntaxHighlighter
    /// Retained here: `NSTextStorage.delegate` is weak.
    private var wideningDelegate: EditWideningStorageDelegate?

    /// - widensEdits: install the ``EditWideningStorageDelegate`` experiment.
    /// - sizePolicy: the H5 size fallback; unbounded by default, so these
    ///   harnesses keep measuring Neon itself at every size.
    init(
        text: String,
        widensEdits: Bool = false,
        theme: Theme = BundledThemes.light,
        sizePolicy: @escaping (String?) -> HighlightingSizePolicy? = { _ in nil }
    ) {
        system = EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: .default)
        system.textView.frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
        highlighter = NeonSyntaxHighlighter(
            textSystem: system,
            languageID: "markdown",
            theme: theme,
            registry: GrammarRegistry(),
            sizePolicy: sizePolicy
        )
        if widensEdits, let storage = system.textView.textStorage, let neon = storage.delegate {
            let delegate = EditWideningStorageDelegate(downstream: neon)
            storage.delegate = delegate
            wideningDelegate = delegate
        }
    }

    /// Mount through the actual EditorView/store before attaching the same production highlighter.
    init(system: EditorTextSystem, registry: GrammarRegistry) {
        self.system = system
        highlighter = NeonSyntaxHighlighter(
            textSystem: system, languageID: "markdown", theme: BundledThemes.light,
            registry: registry, sizePolicy: { _ in nil }
        )
    }

    var textView: NSTextView {
        system.textView
    }

    /// The rendering attributes Neon has applied, as merged runs of a
    /// comparable signature (colour, font traits, underline).
    func renderedRuns() -> [RenderedRun] {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return [] }
        let origin = contentManager.documentRange.location
        var runs: [RenderedRun] = []
        layoutManager.enumerateRenderingAttributes(from: origin, reverse: false) { _, attributes, textRange in
            let location = contentManager.offset(from: origin, to: textRange.location)
            let length = contentManager.offset(from: textRange.location, to: textRange.endLocation)
            let signature = RenderedRun.signature(of: attributes)
            guard !signature.isEmpty, length > 0 else { return true }
            if let last = runs.last, last.signature == signature, NSMaxRange(last.range) == location {
                runs[runs.count - 1].range.length += length
            } else {
                runs.append(RenderedRun(range: NSRange(location: location, length: length), signature: signature))
            }
            return true
        }
        return runs
    }
}

struct RenderedRun: Equatable, CustomStringConvertible {
    var range: NSRange
    let signature: String

    static func signature(of attributes: [NSAttributedString.Key: Any]) -> String {
        var parts: [String] = []
        if let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB) {
            parts.append(String(
                format: "c%02x%02x%02x",
                Int(color.redComponent * 255),
                Int(color.greenComponent * 255),
                Int(color.blueComponent * 255)
            ))
        }
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            parts.append("f\(traits.contains(.bold) ? "b" : "")\(traits.contains(.italic) ? "i" : "")")
        }
        if attributes[.underlineStyle] != nil {
            parts.append("u")
        }
        return parts.joined(separator: ",")
    }

    var description: String {
        "\(range.location)+\(range.length):\(signature)"
    }
}

extension HighlightedEditor {
    /// Waits until Neon has styled something and then styled nothing more for
    /// `quietPeriod`. Returns false on timeout.
    @discardableResult
    func waitUntilQuiet(
        quietPeriod: Duration = .seconds(1),
        timeout: Duration = .seconds(120),
        requireActivityAfter baseline: Int? = nil
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var lastCount = highlighter.styledTokenCount
        var lastChange = clock.now
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            let count = highlighter.styledTokenCount
            if count != lastCount {
                lastCount = count
                lastChange = clock.now
                continue
            }
            let active = count > (baseline ?? 0)
            if active, clock.now - lastChange >= quietPeriod {
                return true
            }
        }
        return false
    }

    /// Polls until the rendered runs equal `expected`. Returns the time taken,
    /// or nil on timeout.
    func waitUntilRuns(equal expected: [RenderedRun], timeout: Duration = .seconds(120)) async -> Duration? {
        let clock = ContinuousClock()
        let start = clock.now
        while clock.now - start < timeout {
            if renderedRuns() == expected {
                return clock.now - start
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    /// Types one character at `location`, or deletes the one there, the way
    /// AppKit's key handling does (`insertText(_:replacementRange:)`).
    func typeOrDelete(at location: Int, insert: Bool) {
        if insert {
            textView.insertText("x", replacementRange: NSRange(location: location, length: 0))
        } else {
            textView.insertText("", replacementRange: NSRange(location: location, length: 1))
        }
    }
}

/// Per-edit measurements of a typing run.
struct TypingRunResult: CustomStringConvertible {
    /// Longest main-thread stall attributed to each edit (from its start to the next).
    let stall: StallStats
    /// Wall-clock duration of the synchronous edit call itself.
    let editCall: StallStats
    /// Main-thread CPU time of the synchronous edit call itself.
    let editCallCPU: StallStats

    var description: String {
        "stall[\(stall)] editCall[\(editCall)] editCallCPU[\(editCallCPU)]"
    }
}

extension HighlightedEditor {
    /// Types `edits` keystrokes (alternating insert / delete, so the document
    /// keeps its size) at `location`, `cadence` apart, while a
    /// ``MainThreadStallMonitor`` watches the main thread. After the last edit
    /// it keeps watching until Neon has been quiet for `settle`.
    func measureTyping(
        edits: Int,
        at location: Int,
        cadence: Duration = .milliseconds(50),
        settle: Duration = .seconds(2)
    ) async -> TypingRunResult {
        let monitor = MainThreadStallMonitor()
        monitor.start()
        try? await Task.sleep(for: .milliseconds(100))
        // Styling may complete during a synchronous edit. Comparing only with
        // the post-typing count would mistake that completed work for a hang.
        let baseline = highlighter.styledTokenCount

        var windowStarts: [UInt64] = []
        var callWall: [Double] = []
        var callCPU: [Double] = []
        for index in 0 ..< edits {
            windowStarts.append(DispatchTime.now().uptimeNanoseconds)
            let cpuStart = currentThreadCPUMilliseconds()
            let wallStart = DispatchTime.now().uptimeNanoseconds
            typeOrDelete(at: location, insert: index.isMultiple(of: 2))
            callWall.append(Double(DispatchTime.now().uptimeNanoseconds - wallStart) / 1e6)
            callCPU.append(currentThreadCPUMilliseconds() - cpuStart)
            try? await Task.sleep(for: cadence)
        }
        let settled = await waitUntilQuiet(quietPeriod: settle, timeout: .seconds(900), requireActivityAfter: baseline)
        #expect(settled, "keystroke benchmark did not observe settled highlighting")
        let end = DispatchTime.now().uptimeNanoseconds
        monitor.stop()

        var stalls: [Double] = []
        for (index, start) in windowStarts.enumerated() {
            let windowEnd = index + 1 < windowStarts.count ? windowStarts[index + 1] : end
            stalls.append(monitor.maxStall(endingIn: start, windowEnd))
        }
        return TypingRunResult(
            stall: StallStats(values: stalls),
            editCall: StallStats(values: callWall),
            editCallCPU: StallStats(values: callCPU)
        )
    }
}
