@testable import CommandBridge
import Darwin
import Foundation
import Testing

extension CommandEndpointTransportTests {
    @Test func finalEndpointIsAbsentUntilTheBoundSocketIsPrivateAndListening() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(3)),
                                                       afterBind: {
                                                           var attributes = stat()
                                                           #expect(lstat(location.socketPath, &attributes) == -1)
                                                           #expect(errno == ENOENT)
                                                       })
            defer { listener.close() }
            var attributes = stat()
            #expect(lstat(location.socketPath, &attributes) == 0)
            #expect(attributes.st_mode & S_IFMT == S_IFSOCK)
            #expect(attributes.st_mode & 0o7777 == 0o600)
        }
    }

    @Test func anUnfamiliarFinalEntrySurvivesStagedPublicationFailure() throws {
        try withLocation { location in
            let marker = Data("preserve foreign final entry".utf8)
            #expect(throws: CommandEndpointError.unavailable(EEXIST)) {
                try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(3)), afterBind: {
                    try marker.write(to: URL(fileURLWithPath: location.socketPath), options: .withoutOverwriting)
                })
            }
            let preserved = try Data(contentsOf: URL(fileURLWithPath: location.socketPath))
            #expect(preserved == marker)
            let entries = try FileManager.default.contentsOfDirectory(atPath: location.directory.path)
            #expect(Set(entries) == ["lock", "s"])
        }
    }

    @Test func interruptedPreparationRetiresOnlyItsOwnedStagingSocket() throws {
        try withLocation { location in
            #expect(throws: CommandSocketError.cancelled) {
                try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(3)), afterBind: {
                    throw CommandSocketError.cancelled
                })
            }
            #expect(!FileManager.default.fileExists(atPath: location.socketPath))
            let entries = try FileManager.default.contentsOfDirectory(atPath: location.directory.path)
            #expect(entries == ["lock"])
        }
    }

    @Test func maximumLengthEndpointUsesAnEquallyBoundedStagingName() throws {
        try withLocation { initial in
            let maximum = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1
            let overhead = initial.directory.lastPathComponent.utf8.count + 3
            let length = maximum - overhead - initial.runtimeDirectory.path.utf8.count - 1
            let runtime = initial.runtimeDirectory.appendingPathComponent(String(repeating: "a", count: length))
            try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let location = try CommandEndpointLocation(runtimeDirectory: runtime, productIdentity: "test.boundary")
            #expect(location.socketPath.utf8.count == maximum)
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(3)),
                                                       afterBind: {
                                                           var attributes = stat()
                                                           #expect(lstat(location.socketPath, &attributes) == -1)
                                                           #expect(errno == ENOENT)
                                                       })
            defer { listener.close() }
            #expect(try CommandEndpointNamespace(location).socketIdentity() != nil)
        }
    }
}
