@testable import EditorCore
import Foundation
import Testing

struct FencedRegionPrefixAdmissionTests {
    @Test(arguments: ["\n", "\r", "\r\n"])
    func longPlainLinesAndFenceContentsKeepTheirClassification(separator: String) {
        let indentation = String(repeating: " ", count: 200_000)
        let prose = (indentation + "```swift") as NSString
        #expect(FencedRegionClassifier.classify(text: prose, atUTF16Offset: prose.length) == .prose)
        let inside = ("```swift" + separator + indentation) as NSString
        #expect(FencedRegionClassifier.classify(text: inside, atUTF16Offset: inside.length)
            == .fencedCode(languageID: "swift"))
    }

    @Test func aDashPrefixStillRequiresAnExactFirstLine() {
        for opening in ["---suffix", "----", "--", "-", ""] {
            let source = (opening + "\nvalue: 1\n---\nbody") as NSString
            #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: opening.utf16.count + 2) == .prose)
        }
        let trailingSpace = "--- \nvalue: 1\n---\nbody" as NSString
        #expect(FencedRegionClassifier.classify(text: trailingSpace, atUTF16Offset: 6) == .frontMatter)
        let valid = "---\rvalue: 1\r...\rbody" as NSString
        #expect(FencedRegionClassifier.classify(text: valid, atUTF16Offset: 7) == .frontMatter)
    }

    @Test func malformedUTF16DoesNotHideTheFenceBoundary() throws {
        let units: [unichar] = [0xD800, 10, 96, 96, 96, 115, 119, 105, 102, 116, 10, 32, 0xDC00]
        let source = try units.withUnsafeBufferPointer { pointer in
            let base = try #require(pointer.baseAddress)
            return NSString(characters: base, length: pointer.count)
        }
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length)
            == .fencedCode(languageID: "swift"))
    }
}
