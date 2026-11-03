import Darwin
import Foundation
@testable import LocalResourceAccess
import Testing

struct ResourceReadAccountingTests {
    @Test func theExactByteLimitIncludesTheEOFCheckButNoExtraPayload() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("1234", to: "a")
        let lease = try DirectoryLease(opening: tree.root)
        let meter = ResourceReadAccounting(maxAttempts: 2, maxBytes: 4)
        #expect(try ContainedResourceReader.read(
            ResourceReference.parse("a"), in: lease, maxBytes: 4, accounting: meter
        ).bytes == Data("1234".utf8))
        #expect(throws: ResourceReadError.workLimit) {
            try ContainedResourceReader.read(ResourceReference.parse("a"), in: lease, maxBytes: 4, accounting: meter)
        }
    }

    @Test func anOversizedReadConsumesOnlyOneOverLimitProbe() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "x", count: 100_000), to: "a")
        let lease = try DirectoryLease(opening: tree.root)
        let meter = ResourceReadAccounting(maxAttempts: 8, maxBytes: 3)
        #expect(throws: ResourceReadError.workLimit) {
            try ContainedResourceReader.read(
                ResourceReference.parse("a"),
                in: lease,
                maxBytes: 100_000,
                accounting: meter
            )
        }
        #expect(meter.readAllowance(upTo: 65536) == 1)
        #expect(throws: ResourceReadError.workLimit) { try meter.beginAttempt() }
    }

    @Test func postReadMutationDoesNotRefundAlreadyConsumedBytes() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "x", count: 100_000), to: "a")
        let lease = try DirectoryLease(opening: tree.root)
        let url = tree.root.appendingPathComponent("a")
        let meter = ResourceReadAccounting(maxAttempts: 8, maxBytes: 100_000)
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { done in
            if done > 0 {
                _ = truncate(url.path, 1)
            }
        }
        #expect(throws: ResourceReadError.changedDuringRead) {
            try ContainedResourceReader.read(
                ResourceReference.parse("a"), in: lease, maxBytes: 100_000,
                cancellation: ResourceCancellation(), hooks: hooks, accounting: meter
            )
        }
        #expect(meter.readAllowance(upTo: 100_000) == 100_000 - 65536 + 1)
    }

    @Test func missingAndOversizedCandidatesConsumeAttemptsWithoutReadingPayload() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("1234", to: "a")
        let lease = try DirectoryLease(opening: tree.root)
        let meter = ResourceReadAccounting(maxAttempts: 2, maxBytes: 8)
        #expect(throws: ResourceReadError.unavailable(ENOENT)) {
            try ContainedResourceReader.read(
                ResourceReference.parse("missing"),
                in: lease,
                maxBytes: 8,
                accounting: meter
            )
        }
        #expect(throws: ResourceReadError.oversized) {
            try ContainedResourceReader.read(ResourceReference.parse("a"), in: lease, maxBytes: 2, accounting: meter)
        }
        #expect(meter.readAllowance(upTo: 8) == 8)
        #expect(throws: ResourceReadError.workLimit) {
            try ContainedResourceReader.read(ResourceReference.parse("a"), in: lease, maxBytes: 8, accounting: meter)
        }
    }

    @Test func cancellationBeforeReadDoesNotSpendAnAttempt() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("1", to: "a")
        let lease = try DirectoryLease(opening: tree.root)
        let meter = ResourceReadAccounting(maxAttempts: 1, maxBytes: 1)
        let cancellation = ResourceCancellation()
        cancellation.cancel()
        #expect(throws: ResourceReadError.cancelled) {
            try ContainedResourceReader.read(
                ResourceReference.parse("a"), in: lease, maxBytes: 1, cancellation: cancellation, accounting: meter
            )
        }
        #expect(try ContainedResourceReader.read(
            ResourceReference.parse("a"), in: lease, maxBytes: 1, accounting: meter
        ).bytes == Data("1".utf8))
    }
}
