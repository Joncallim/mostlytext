import Darwin
@testable import FileCore
import Foundation
import Testing

/// Review pass 9: on a FAT32 volume the driver advertises no swap support but accepts RENAME_SWAP, returns 0 and does a
/// plain rename that deletes the previous file. Every save then looked like a failed exchange ("preserved a competing
/// version at <temp>" — a file that does not exist) and a competing external write was silently destroyed. (Verified
/// by the reviewer on a real hdiutil FAT32 image; the host cannot mount one here, so the driver is simulated.)
struct FileStoreFAT32PublicationTests {
    private func plainRenameInsteadOfSwap() -> ConditionalPublicationTestHooks {
        ConditionalPublicationTestHooks(swapOverride: { temporary, destination in
            let result = temporary.path.withCString { source in
                destination.path.withCString { target in rename(source, target) }
            }
            return result == 0 ? 0 : errno
        })
    }

    @Test func aSwapThatBehavesAsAPlainRenameIsAcceptedNotReportedAsARecoveryFailure() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore(conditionalPublicationHooks: plainRenameInsteadOfSwap())
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store).load().edited(text: "ours")

        _ = try dirty.save()

        #expect(try String(contentsOf: fixture.url, encoding: .utf8) == "ours")
        let directory = fixture.url.deletingLastPathComponent()
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains(".private-stage-") }
        #expect(leftovers.isEmpty)
    }

    @Test func aStaleBaselineIsStillRefusedWhenTheVolumeCannotExchange() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store =
            FileStore(conditionalPublicationHooks: ConditionalPublicationTestHooks(simulateSwapUnsupported: true))
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store).load().edited(text: "ours")
        try "external edit that is longer".write(to: fixture.url, atomically: false, encoding: .utf8)

        #expect(throws: FileStoreError.self) { _ = try dirty.save() }
        #expect(try String(contentsOf: fixture.url, encoding: .utf8) == "external edit that is longer")
    }
}
