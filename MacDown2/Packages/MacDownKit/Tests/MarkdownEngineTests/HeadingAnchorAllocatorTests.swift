@testable import MarkdownEngine
import Testing

struct HeadingAnchorAllocatorTests {
    @Test func reservesAuthoredIDsAndAllocatesDuplicatesGlobally() {
        var allocator = HeadingAnchorAllocator(reservedIDs: ["overview", "A", "a-1"])
        #expect(allocator.allocate(title: "Overview") == "overview-1")
        #expect(allocator.allocate(title: "A") == "a")
        #expect(allocator.allocate(title: "A") == "a-2")
        #expect(allocator.allocate(title: "A-1") == "a-1-1")

        var unreserved = HeadingAnchorAllocator()
        #expect(unreserved.allocate(title: "A") == "a")
        #expect(unreserved.allocate(title: "A") == "a-1")
        #expect(unreserved.allocate(title: "A-1") == "a-1-1")
    }

    @Test func normalizesUnicodeWithoutLocaleDependentNaming() {
        var allocator = HeadingAnchorAllocator()
        #expect(allocator.allocate(title: "  Café   東京  ") == "café-東京")
        #expect(allocator.allocate(title: "Cafe\u{301} 東京") == "café-東京-1")
        #expect(allocator.allocate(title: "!!!") == "section")
        #expect(allocator.allocate(title: "  _ a - B _ ") == "_-a---b-_")
    }

    @Test func authoredIdentifiersUseExactUnicodeSpelling() {
        let decomposed = "cafe\u{301}"
        let composed = "café"
        #expect(decomposed == composed)
        #expect(!decomposed.utf8.elementsEqual(composed.utf8))
        var distinct = HeadingAnchorAllocator(reservedIDs: [decomposed])
        #expect(distinct.allocate(title: composed).utf8.elementsEqual(composed.utf8))
        var collision = HeadingAnchorAllocator(reservedIDs: [composed])
        #expect(collision.allocate(title: composed) == "café-1")
    }

    @Test func repeatedHeadingsKeepTheirSuffixAfterOtherFamiliesAndAuthoredReservations() {
        var allocator = HeadingAnchorAllocator(reservedIDs: ["a-1", "a-3"])
        #expect(allocator.allocate(title: "A") == "a")
        #expect(allocator.allocate(title: "A-2") == "a-2")
        let repeated = (0 ..< 3000).map { _ in allocator.allocate(title: "A") }
        #expect(repeated.first == "a-4" && repeated.last == "a-3003")
        #expect(Set(repeated).count == 3000)
        #expect(allocator.allocate(title: "A-4") == "a-4-1")
        #expect(allocator.allocate(title: "A") == "a-3004")
    }

    @Test func longFragmentsRemainBoundedAndRepeatable() {
        let title = String(repeating: "漢字", count: 100)
        var first = HeadingAnchorAllocator()
        var second = HeadingAnchorAllocator()
        let initial = first.allocate(title: title)
        let duplicate = first.allocate(title: title)
        #expect(initial == second.allocate(title: title))
        #expect(initial != duplicate)
        #expect(initial.utf8.count <= 256)
        #expect(duplicate.utf8.count <= 256)
        #expect(initial.hasSuffix("-\(String(initial.suffix(12)))"))
    }
}
