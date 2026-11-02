import CommandBridge
import CommandLineSupport
import Darwin
import Foundation
import Testing

struct CommandLineStdinTests {
    private final class InputPipe {
        let reader: Int32
        var writer: Int32

        init() throws {
            var descriptors: [Int32] = [-1, -1]
            try #require(pipe(&descriptors) == 0)
            reader = descriptors[0]; writer = descriptors[1]
        }

        func put(_ bytes: Data) throws {
            let count = bytes.withUnsafeBytes { Darwin.write(writer, $0.baseAddress, $0.count) }
            try #require(count == bytes.count)
            Darwin.close(writer); writer = -1
        }

        deinit {
            Darwin.close(reader)
            if writer >= 0 {
                Darwin.close(writer)
            }
        }
    }

    @Test(arguments: [Data(), Data([239, 187, 191]) + Data("漢\r\nend".utf8)])
    func exactStdinAndFlagsSurviveEOF(_ bytes: Data) throws {
        let input = try InputPipe()
        let flags = fcntl(input.reader, F_GETFL)
        try input.put(bytes)
        #expect(try CommandLineStdin.read(descriptor: input.reader, until: .now.advanced(by: .seconds(5))) == bytes)
        #expect(fcntl(input.reader, F_GETFL) == flags)
    }

    @Test func invalidUTF8AndTimeoutRestoreTheCallersDescriptor() throws {
        let invalid = try InputPipe()
        let invalidFlags = fcntl(invalid.reader, F_GETFL)
        try invalid.put(Data([255]))
        #expect(throws: CommandLineInputFailure.invalidUTF8) {
            try CommandLineStdin.read(descriptor: invalid.reader, until: .now.advanced(by: .seconds(5)))
        }
        #expect(fcntl(invalid.reader, F_GETFL) == invalidFlags)
        let stalled = try InputPipe()
        let flags = fcntl(stalled.reader, F_GETFL)
        #expect(throws: CommandLineInputFailure.timedOut) {
            try CommandLineStdin.read(descriptor: stalled.reader, until: .now.advanced(by: .milliseconds(10)))
        }
        #expect(fcntl(stalled.reader, F_GETFL) == flags)
    }

    @Test func cancellationIsObservedWithoutClosingOrReadingStdin() throws {
        let input = try InputPipe()
        let flags = fcntl(input.reader, F_GETFL)
        #expect(throws: CommandLineInputFailure.cancelled) {
            try CommandLineStdin.read(
                descriptor: input.reader,
                until: .now.advanced(by: .seconds(5)),
                isCancelled: { true }
            )
        }
        #expect(fcntl(input.reader, F_GETFL) == flags)
        try input.put(Data("still present".utf8))
        #expect(try CommandLineStdin.read(descriptor: input.reader, until: .now.advanced(by: .seconds(5))) ==
            Data("still present".utf8))
    }

    @Test func oversizedRegularInputIsBoundedAndFlagsAreRestored() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 65, count: CommandProtocol.maximumStdinBytes + 1).write(to: file)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let flags = fcntl(handle.fileDescriptor, F_GETFL)
        #expect(throws: CommandLineInputFailure.tooLarge) {
            try CommandLineStdin.read(descriptor: handle.fileDescriptor, until: .now.advanced(by: .seconds(5)))
        }
        #expect(fcntl(handle.fileDescriptor, F_GETFL) == flags)
    }
}
