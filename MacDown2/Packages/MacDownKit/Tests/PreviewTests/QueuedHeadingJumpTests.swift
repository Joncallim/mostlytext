import Foundation
import MarkdownEngine
@testable import Preview
import Testing

@MainActor
private final class HeadingJumpProbe {
    var valid = true
    var checks = 0
}

@MainActor
struct QueuedHeadingJumpTests {
    @Test func sourceAuthorityIsCheckedAtConsumptionAndNeverBecomesAnOrdinaryFraction() async throws {
        let controller = try await controller()
        let probe = HeadingJumpProbe()
        controller.queueHeadingJump(toLine: 5, animated: false) {
            probe.checks += 1
            return probe.valid
        }
        #expect(probe.checks == 0 && controller.headingJumpID != nil)
        #expect(controller.targetPreviewFraction == nil && controller.targetPreviewBlock == nil)
        let target = try #require(controller.consumeHeadingJump())
        #expect(probe.checks == 1 && target.block.blockIndex == 2 && !target.animated)
        #expect(controller.headingJumpID == nil && controller.targetPreviewFraction == nil)
        #expect(controller.consumeHeadingJump() == nil)
    }

    @Test func aSourceChangeBetweenPressAndConsumptionDropsTheJump() async throws {
        let controller = try await controller()
        let probe = HeadingJumpProbe()
        controller.queueHeadingJump(toLine: 5, animated: true) {
            probe.checks += 1
            return probe.valid
        }
        probe.valid = false
        #expect(controller.consumeHeadingJump() == nil)
        #expect(probe.checks == 1 && controller.headingJumpID == nil)
        #expect(controller.targetPreviewFraction == nil)
    }

    @Test func onlyTheNewestPendingHeadingActionCanBeConsumed() async throws {
        let controller = try await controller()
        let first = HeadingJumpProbe(), second = HeadingJumpProbe()
        controller.queueHeadingJump(toLine: 5, animated: true) { first.checks += 1; return first.valid }
        let oldID = controller.headingJumpID
        controller.queueHeadingJump(toLine: 1, animated: false) { second.checks += 1; return second.valid }
        #expect(controller.headingJumpID != oldID)
        let target = try #require(controller.consumeHeadingJump())
        #expect(target.block.blockIndex == 0 && first.checks == 0 && second.checks == 1)
    }

    @Test func queuedNavigationDoesNotKeepAWeakHostAlive() async throws {
        let controller = try await controller()
        var probe: HeadingJumpProbe? = HeadingJumpProbe()
        controller.queueHeadingJump(toLine: 5, animated: true) { [weak owner = probe] in owner?.valid == true }
        probe = nil
        #expect(controller.consumeHeadingJump() == nil)
        #expect(controller.headingJumpID == nil)
    }

    private func controller() async throws -> ScrollSyncController {
        let source = "# First\n\nParagraph\n\n## Last\n"
        let document = try await ParseEngine().parse(source, revision: 1)
        let blocks = PreviewBlock.blocks(from: document, text: source)
        try #require(blocks.count == 3)
        return ScrollSyncController(map: ScrollSyncMap(blocks: blocks), blockHeights: [0: 100, 1: 100, 2: 100])
    }
}
