import Darwin
import Foundation
@testable import LocalResourceAccess
import Testing

/// Real-filesystem containment tests for #121 stage A. Every "outside" sentinel lives in a separate disposable
/// directory; a test fails if those bytes ever reach the result. Races are produced with hooks that sit around the
/// real `openat`/`read`, never by faking the read.
@Suite(.serialized)
struct ContainedResourceReaderTests {
    // MARK: - Positive controls

    @Test func readsAnOrdinaryFileAndReportsItsMIMEHint() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("body{}", to: "sub/style.css")
        let lease = try DirectoryLease(opening: tree.root)

        let snapshot = try ContainedResourceReader.read(
            ResourceTestSupport.reference("/sub/style.css"),
            in: lease,
            maxBytes: 1024
        )

        #expect(snapshot.bytes == Data("body{}".utf8))
        #expect(snapshot.mimeHint == "text/css")
        #expect(snapshot.name == "style.css")
    }

    @Test func aSymlinkThatStaysInsideTheRootIsReadThroughTheHint() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("real", to: "real.txt")
        try FileManager.default.createSymbolicLink(
            atPath: tree.root.appendingPathComponent("alias.txt").path, withDestinationPath: "real.txt"
        )
        let lease = try DirectoryLease(opening: tree.root)

        let snapshot = try ContainedResourceReader.read(
            ResourceTestSupport.reference("alias.txt"),
            in: lease,
            maxBytes: 1024
        )

        #expect(snapshot.bytes == Data("real".utf8))
        #expect(snapshot.name == "real.txt")
    }

    // MARK: - Outside objects

    @Test func anOutsideLeafSymlinkIsDenied() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try FileManager.default.createSymbolicLink(
            at: tree.root.appendingPathComponent("leak.txt"),
            withDestinationURL: tree.outside.appendingPathComponent("secret.txt")
        )
        let lease = try DirectoryLease(opening: tree.root)

        #expect(throws: ResourceReadError.denied) {
            try ContainedResourceReader.read(ResourceTestSupport.reference("leak.txt"), in: lease, maxBytes: 1024)
        }
    }

    @Test func anOutsideDirectorySymlinkIsDenied() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try FileManager.default.createSymbolicLink(
            at: tree.root.appendingPathComponent("dir"), withDestinationURL: tree.outside
        )
        let lease = try DirectoryLease(opening: tree.root)

        #expect(throws: ResourceReadError.denied) {
            try ContainedResourceReader.read(ResourceTestSupport.reference("dir/secret.txt"), in: lease, maxBytes: 1024)
        }
    }

    @Test func aLeafReplacedByAnOutsideSymlinkBetweenTheHintAndTheOpenIsDenied() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("inside", to: "swap.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let leaf = tree.root.appendingPathComponent("swap.txt")
        let secret = tree.outside.appendingPathComponent("secret.txt")
        var hooks = ResourceReadHooks()
        hooks.beforeOpen = {
            try? FileManager.default.removeItem(at: leaf)
            try? FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: secret)
        }

        var snapshot: ResourceSnapshot?
        #expect(throws: ResourceReadError.denied) {
            snapshot = try ContainedResourceReader.read(
                ResourceTestSupport.reference("swap.txt"), in: lease, maxBytes: 1024,
                cancellation: ResourceCancellation(), hooks: hooks
            )
        }
        #expect(!ResourceTestSupport.leaked(snapshot), "outside bytes leaked")
    }

    @Test func anIntermediateDirectoryReplacedByAnOutsideSymlinkBeforeTheOpenIsDenied() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("inside", to: "sub/file.txt")
        try ResourceTestSupport.secret.write(
            to: tree.outside.appendingPathComponent("file.txt"),
            atomically: false,
            encoding: .utf8
        )
        let lease = try DirectoryLease(opening: tree.root)
        let sub = tree.root.appendingPathComponent("sub")
        let away = tree.root.appendingPathComponent("sub-away")
        var hooks = ResourceReadHooks()
        hooks.beforeOpen = {
            try? FileManager.default.moveItem(at: sub, to: away)
            try? FileManager.default.createSymbolicLink(at: sub, withDestinationURL: tree.outside)
        }

        var snapshot: ResourceSnapshot?
        #expect(throws: ResourceReadError.denied) {
            snapshot = try ContainedResourceReader.read(
                ResourceTestSupport.reference("sub/file.txt"), in: lease, maxBytes: 1024,
                cancellation: ResourceCancellation(), hooks: hooks
            )
        }
        #expect(!ResourceTestSupport.leaked(snapshot), "outside bytes leaked")
    }

    // MARK: - Root identity

    @Test func aRootNameRedirectedBeforeTheReadIsReportedAsChangedRoot() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("inside", to: "a.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let moved = tree.base.appendingPathComponent("root-moved")
        try FileManager.default.moveItem(at: tree.root, to: moved)
        try FileManager.default.createSymbolicLink(at: tree.root, withDestinationURL: tree.outside)
        try ResourceTestSupport.secret.write(
            to: tree.outside.appendingPathComponent("a.txt"),
            atomically: false,
            encoding: .utf8
        )

        #expect(throws: ResourceReadError.changedRoot) {
            try ContainedResourceReader.read(ResourceTestSupport.reference("a.txt"), in: lease, maxBytes: 1024)
        }
    }

    @Test func aRootRedirectedAfterTheNameCheckStillReadsOnlyTheGrantedDirectory() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("granted-bytes", to: "a.txt")
        try ResourceTestSupport.secret.write(
            to: tree.outside.appendingPathComponent("a.txt"),
            atomically: false,
            encoding: .utf8
        )
        let lease = try DirectoryLease(opening: tree.root)
        let moved = tree.base.appendingPathComponent("root-moved")
        var hooks = ResourceReadHooks()
        hooks.beforeOpen = {
            try? FileManager.default.moveItem(at: tree.root, to: moved)
            try? FileManager.default.createSymbolicLink(at: tree.root, withDestinationURL: tree.outside)
        }

        let snapshot = try ContainedResourceReader.read(
            ResourceTestSupport.reference("a.txt"), in: lease, maxBytes: 1024, cancellation: ResourceCancellation(),
            hooks: hooks
        )

        #expect(
            snapshot.bytes == Data("granted-bytes".utf8),
            "the pinned descriptor, not the pathname, is the authority"
        )
        #expect(!ResourceTestSupport.leaked(snapshot), "outside bytes leaked")
    }

    @Test func renamingAnAncestorDuringTheReadDoesNotRedirectIt() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        let large = String(repeating: "x", count: 150_000)
        try tree.write(large, to: "big.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let renamed = tree.base.appendingPathComponent("renamed-base")
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { done in
            if done > 0 {
                try? FileManager.default.moveItem(at: tree.base, to: renamed)
            }
        }

        let snapshot = try ContainedResourceReader.read(
            ResourceTestSupport.reference("big.txt"), in: lease, maxBytes: 1 << 20,
            cancellation: ResourceCancellation(),
            hooks: hooks
        )

        #expect(snapshot.bytes.count == large.utf8.count)
        try? FileManager.default.moveItem(at: renamed, to: tree.base)
    }

    // MARK: - Object kinds and limits

    @Test func aFIFOIsRejectedAsNonRegularWithoutBlocking() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        #expect(mkfifo(tree.root.appendingPathComponent("pipe").path, 0o600) == 0)
        let lease = try DirectoryLease(opening: tree.root)

        #expect(throws: ResourceReadError.nonRegular) {
            try ContainedResourceReader.read(ResourceTestSupport.reference("pipe"), in: lease, maxBytes: 1024)
        }
    }

    @Test func aFileLargerThanTheCapIsOversizedBeforeAnyBytesAreAdmitted() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "x", count: 2048), to: "big.txt")
        let lease = try DirectoryLease(opening: tree.root)

        #expect(throws: ResourceReadError.oversized) {
            try ContainedResourceReader.read(ResourceTestSupport.reference("big.txt"), in: lease, maxBytes: 1024)
        }
    }

    @Test func aFileThatGrowsPastTheCapWhileBeingReadIsRejectedAndNeverReturnedPartially() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "a", count: 100_000), to: "grow.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let url = tree.root.appendingPathComponent("grow.txt")
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { done in
            guard done > 0, let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(repeating: 0x62, count: 100_000))
        }

        var snapshot: ResourceSnapshot?
        var failure: ResourceReadError?
        do {
            snapshot = try ContainedResourceReader.read(
                ResourceTestSupport.reference("grow.txt"), in: lease, maxBytes: 150_000,
                cancellation: ResourceCancellation(), hooks: hooks
            )
        } catch let error as ResourceReadError {
            failure = error
        }
        #expect(failure == .oversized || failure == .changedDuringRead, "a growing file must not be admitted")
        #expect(snapshot == nil)
    }

    @Test func cancellationBetweenChunksStopsTheRead() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "x", count: 200_000), to: "big.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let cancellation = ResourceCancellation()
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { done in
            if done > 0 {
                cancellation.cancel()
            }
        }

        #expect(throws: ResourceReadError.cancelled) {
            try ContainedResourceReader.read(
                ResourceTestSupport.reference("big.txt"), in: lease, maxBytes: 1 << 20, cancellation: cancellation,
                hooks: hooks
            )
        }
    }
}

/// Same suite (so `.serialized` also isolates the descriptor-count baselines), split out for type-body length.
extension ContainedResourceReaderTests {
    // MARK: - Descriptor ownership

    @Test func failuresReturnTheProcessToItsDescriptorBaseline() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "x", count: 2048), to: "big.txt")
        #expect(mkfifo(tree.root.appendingPathComponent("pipe").path, 0o600) == 0)
        let baseline = ResourceTestSupport.openDescriptorCount(under: tree.base)
        do {
            let lease = try DirectoryLease(opening: tree.root)
            for path in ["big.txt", "pipe", "missing.txt"] {
                _ = try? ContainedResourceReader.read(
                    try ResourceTestSupport.reference(path),
                    in: lease,
                    maxBytes: 1024
                )
            }
            lease.close()
        }
        #expect(
            ResourceTestSupport.openDescriptorCount(under: tree.base) == baseline,
            "no descriptor under the tree may outlive the lease"
        )
    }

    @Test func closingTheLeaseMidReadDoesNotCloseTheDescriptorUnderTheReader() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        let large = String(repeating: "y", count: 200_000)
        try tree.write(large, to: "big.txt")
        let baseline = ResourceTestSupport.openDescriptorCount(under: tree.base)
        let lease = try DirectoryLease(opening: tree.root)
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { done in
            if done > 0 {
                lease.close()
            }
        }

        let snapshot = try ContainedResourceReader.read(
            ResourceTestSupport.reference("big.txt"), in: lease, maxBytes: 1 << 20,
            cancellation: ResourceCancellation(),
            hooks: hooks
        )

        #expect(snapshot.bytes.count == large.utf8.count)
        #expect(
            ResourceTestSupport.openDescriptorCount(under: tree.base) == baseline,
            "the deferred close ran and nothing leaked"
        )
        #expect(throws: ResourceReadError.leaseClosed) {
            try ContainedResourceReader.read(ResourceTestSupport.reference("big.txt"), in: lease, maxBytes: 1 << 20)
        }
    }

    // MARK: - Single-file grant

    @Test func aFileLeaseReadsExactlyTheGrantedFileAndGivesNoDirectoryAuthority() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("only", to: "only.txt")
        try tree.write("neighbour", to: "neighbour.txt")

        let lease = try FileLease(opening: tree.root.appendingPathComponent("only.txt"))
        let snapshot = try ContainedResourceReader.read(lease, maxBytes: 1024)

        #expect(snapshot.bytes == Data("only".utf8))
        #expect(snapshot.name == "only.txt")
        // There is no API to derive a directory grant or read a sibling from a FileLease.
        lease.close()
        #expect(throws: ResourceReadError.leaseClosed) { try ContainedResourceReader.read(lease, maxBytes: 1024) }
    }

    @Test func aFileLeaseRejectsAnythingThatIsNotARegularFile() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        #expect(throws: ResourceReadError.nonRegular) { try FileLease(opening: tree.root) }
    }
}

struct ResourceReferenceTests {
    @Test func stripsQueryAndFragmentStructurallyBeforeDecoding() throws {
        #expect(try ResourceReference.parse("/a/b.css?v=1#x").components == ["a", "b.css"])
        #expect(try ResourceReference.parse("a%3Fb.txt").components == ["a?b.txt"], "an escaped ? is part of the name")
    }

    @Test func decodesEachComponentExactlyOnce() throws {
        #expect(try ResourceReference.parse("/%252e%252e/x").components == ["%2e%2e", "x"])
        #expect(try ResourceReference.parse("/100%25.txt").components == ["100%.txt"])
    }

    @Test func rejectsEncodedSeparatorsNULAndMalformedEscapes() {
        #expect(throws: ResourceReadError.invalidReference) { try ResourceReference.parse("/a%2Fb") }
        #expect(throws: ResourceReadError.invalidReference) { try ResourceReference.parse("/a%00b") }
        #expect(throws: ResourceReadError.invalidReference) { try ResourceReference.parse("/a%zz") }
        #expect(throws: ResourceReadError.invalidReference) { try ResourceReference.parse("/a%2") }
        #expect(throws: ResourceReadError.invalidReference) { try ResourceReference.parse("/") }
    }

    @Test func resolvesDotSegmentsButNeverAboveTheRoot() throws {
        #expect(try ResourceReference.parse("/a/./b/../c.txt").components == ["a", "c.txt"])
        #expect(try ResourceReference.parse("/a/%2e%2e/c.txt").components == ["c.txt"])
        #expect(throws: ResourceReadError.denied) { try ResourceReference.parse("/../x") }
        #expect(throws: ResourceReadError.denied) { try ResourceReference.parse("/a/../../x") }
    }

    @Test func keepsDistinctUnicodeNamesDistinctAndSpecialCharactersIntact() throws {
        let composed = try ResourceReference.parse("/caf%C3%A9.txt").components
        let decomposed = try ResourceReference.parse("/cafe%CC%81.txt").components
        #expect(composed.first?.unicodeScalars.count != decomposed.first?.unicodeScalars.count)
        #expect(try ResourceReference.parse("/a&b%27c%22d.txt").components == ["a&b'c\"d.txt"])
        #expect(try ResourceReference.parse("/%E6%97%A5%E6%9C%AC.png").components == ["日本.png"])
    }
}
