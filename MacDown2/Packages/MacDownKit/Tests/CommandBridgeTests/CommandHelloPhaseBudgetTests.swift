@testable import CommandBridge
import Darwin
import Foundation
import Synchronization
import Testing

extension CommandEndpointTransportTests {
    @Test func admittedHelloDoesNotInheritAnExpiredIdleDeadline() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(2)))
            defer { listener.close() }
            let client = try connectedRawPeer(location)
            defer { client.close() }
            let checks = Mutex(0)
            let idleDeadline = ContinuousClock.now.advanced(by: .milliseconds(40))
            let server = try listener.accept(until: idleDeadline, helloTimeout: .milliseconds(250), isCancelled: {
                let check = checks.withLock { $0 += 1; return $0 }
                if check == 4 {
                    // A connected peer makes poll immediately ready. The fourth
                    // check is writeFrame's first check, after kernel accept.
                    // Deliberately expire that idle turn at this exact phase;
                    // this is not a sleep intended to arrange thread ordering.
                    while ContinuousClock.now < idleDeadline {
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                }
                return false
            })
            defer { server.close() }
            #expect(checks.withLock { $0 } >= 4)
            let hello = try #require(try client.readFrame(until: .now.advanced(by: .seconds(1))))
            #expect(try CommandInstanceHello.decode(hello) == listener.instanceID)
        }
    }

    @Test func exhaustedHelloBudgetClosesThePeerAndLeavesAdmissionUsable() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(2)))
            defer { listener.close() }
            let expired = try connectedRawPeer(location)
            defer { expired.close() }
            #expect(throws: CommandSocketError.timedOut) {
                try listener.accept(until: .now.advanced(by: .seconds(1)), helloTimeout: .zero)
            }
            #expect(try expired.readFrame(until: .now.advanced(by: .seconds(1))) == nil)
            try requireUsableGreeting(listener, location: location)
        }
    }

    @Test func cancellationAtHelloClosesThePeerAndLeavesAdmissionUsable() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(2)))
            defer { listener.close() }
            let cancelled = try connectedRawPeer(location)
            defer { cancelled.close() }
            let checks = Mutex(0)
            #expect(throws: CommandSocketError.cancelled) {
                try listener.accept(until: .now.advanced(by: .seconds(1)), helloTimeout: .milliseconds(250),
                                    isCancelled: { checks.withLock { $0 += 1; return $0 == 4 } })
            }
            #expect(try cancelled.readFrame(until: .now.advanced(by: .seconds(1))) == nil)
            try requireUsableGreeting(listener, location: location)
        }
    }

    private func connectedRawPeer(_ location: CommandEndpointLocation) throws -> CommandSocketConnection {
        let descriptor = try CommandSocketPolling.makeSocket()
        do {
            try CommandSocketPolling.connect(descriptor, path: location.socketPath,
                                             deadline: .now.advanced(by: .seconds(1)), cancelled: { false })
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        return try CommandSocketConnection(adopting: descriptor)
    }

    private func requireUsableGreeting(_ listener: CommandEndpointListener,
                                       location: CommandEndpointLocation) throws {
        let client = try connectedRawPeer(location)
        defer { client.close() }
        let server = try listener.accept(until: .now.advanced(by: .seconds(1)), helloTimeout: .milliseconds(250))
        defer { server.close() }
        let hello = try #require(try client.readFrame(until: .now.advanced(by: .seconds(1))))
        #expect(try CommandInstanceHello.decode(hello) == listener.instanceID)
    }
}
