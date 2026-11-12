import Darwin
import Foundation
import QuickLookSource
import Testing

/// Compiles the shipping worker process controller into the app test bundle.
/// The fake child isolates deadline and descriptor behavior from XPC/Finder.
@Suite("Quick Look worker process boundary", .serialized)
struct QuickLookSourceProcessTests {
    @Test func inheritedSelectedDescriptorAndOutputDescriptorWork() throws {
        let fixture = try QuickLookSourceProcessFixture(mode: .echo)
        defer { fixture.remove() }
        let result = SourceProcess.run(selectedDescriptor: fixture.selected.fileDescriptor,
                                       executable: fixture.executable)
        #expect(result.status == .complete)
        #expect(try String(data: #require(result.data), encoding: .utf8)
            == "<html><body># selected</body></html>")
    }

    @Test(.timeLimit(.minutes(1)))
    func blockedChildIsKilledReapedAndReturnsAtDeadline() throws {
        let fixture = try QuickLookSourceProcessFixture(mode: .sleep)
        defer { fixture.remove() }

        let started = ProcessInfo.processInfo.systemUptime
        let result = SourceProcess.run(selectedDescriptor: fixture.selected.fileDescriptor,
                                       executable: fixture.executable)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        #expect(result.status == .timedOut)
        #expect(result.data == nil)
        #expect(elapsed >= 2.9 && elapsed < 5.0)
        let pid = try #require(Int32(String(contentsOf: fixture.pidFile, encoding: .utf8)))
        var status: Int32 = 0
        let waited = Darwin.waitpid(pid, &status, WNOHANG)
        let waitError = errno
        #expect(waited == -1 && waitError == ECHILD, "The timed-out child was not reaped")
    }
}

private struct QuickLookSourceProcessFixture {
    enum Mode { case echo, sleep }

    let directory: URL
    let executable: URL
    let pidFile: URL
    let selected: FileHandle

    init(mode: Mode) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-ql-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent("MostlyTextQuickLookWorker")
        pidFile = directory.appendingPathComponent("child.pid")
        let script = switch mode {
        case .echo:
            "#!/bin/sh\nIFS= read -r line <&3\nprintf '<html><body>%s</body></html>' \"$line\" >&4\n"
        case .sleep:
            "#!/bin/sh\nprintf '%s' \"$$\" > '\(pidFile.path)'\nexec /bin/sleep 60\n"
        }
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let input = directory.appendingPathComponent("selected.md")
        try Data("# selected\n".utf8).write(to: input)
        selected = try FileHandle(forReadingFrom: input)
    }

    func remove() {
        try? selected.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
