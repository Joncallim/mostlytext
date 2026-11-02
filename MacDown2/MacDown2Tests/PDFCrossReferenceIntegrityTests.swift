import Foundation
@testable import MacDown2
import PDFKit
import Testing

@MainActor
struct PDFCrossReferenceIntegrityTests {
    @Test func scratchAdmissionRepairsOnlyAVisibleUnreferencedOrphan() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFCrossReferenceIntegrity-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let original = makePDF(orphan: true)
        try original.write(to: scratch)
        let repaired = PDFExportAdapter.normalizedPrintableData(original, sourceHasContent: true)
        #expect(repaired == PDFCrossReferenceIntegrity.normalized(original))
        #expect(repaired != nil)
        #expect(try Data(contentsOf: scratch) == original)

        let referenced = makePDF(orphan: true, reference: "5 0 R")
        try referenced.write(to: scratch)
        #expect(try PDFExportAdapter.normalizedPrintableData(Data(contentsOf: scratch), sourceHasContent: true) == nil)
        #expect(try Data(contentsOf: scratch) == referenced)

        let trailerReferenced = makePDF(orphan: true, trailerExtra: "/Info 5 0 R")
        try trailerReferenced.write(to: scratch)
        #expect(try PDFExportAdapter.normalizedPrintableData(Data(contentsOf: scratch), sourceHasContent: true) == nil)
        #expect(try Data(contentsOf: scratch) == trailerReferenced)
    }

    @Test func orphanSlotIsFreedWithoutChangingPageObjects() throws {
        let original = makePDF(orphan: true)
        let repaired = try #require(PDFCrossReferenceIntegrity.normalized(original))
        let xref = try #require(original.range(of: Data("xref\n".utf8)))
        #expect(repaired.count == original.count)
        #expect(repaired != original)
        #expect(original.prefix(xref.lowerBound) == repaired.prefix(xref.lowerBound))
        #expect(PDFCrossReferenceIntegrity.normalized(repaired) == repaired)
        #expect(try #require(PDFDocument(data: repaired)).pageCount == 1)
        #expect(String(bytes: repaired, encoding: .utf8)?.contains("0000000000 00000 f") == true)
    }

    @Test func existingValidTableRemainsByteIdentical() {
        let valid = makePDF()
        #expect(PDFCrossReferenceIntegrity.normalized(valid) == valid)
    }

    @Test func referencedOrWrongOffsetObjectIsRejected() {
        #expect(PDFCrossReferenceIntegrity.normalized(makePDF(orphan: true, reference: "5 0 R")) == nil)
        #expect(PDFCrossReferenceIntegrity.normalized(makePDF(orphan: true, reference: "5\n0 R")) == nil)
        #expect(PDFCrossReferenceIntegrity.normalized(makePDF(orphan: true, reference: "5% note\n0 R")) == nil)
        #expect(PDFCrossReferenceIntegrity.normalized(makePDF(orphan: true, reference: "5 1 R")) == nil)
        #expect(PDFCrossReferenceIntegrity.normalized(makePDF(orphan: true, trailerExtra: "/Info 5 0 R")) == nil)
        let valid = makePDF()
        let damaged = Data((String(bytes: valid, encoding: .utf8) ?? "")
            .replacingOccurrences(of: "0000000009 00000 n", with: "0000000001 00000 n").utf8)
        #expect(damaged != valid)
        #expect(PDFCrossReferenceIntegrity.normalized(damaged) == nil)
    }

    @Test func literalHexAndStreamBytesAreNotObjectReferences() {
        let note = "/Note (literal 5 0 R and 5 0 obj) /Escaped (\\(5 0 R\\)) /Hex <3520302052>"
        let stream = "0 0 0 rg 10 10 20 20 re f\n(5 0 R) (5 0 obj)"
        let original = makePDF(orphan: true, catalogExtra: note, streamContent: stream)
        #expect(PDFCrossReferenceIntegrity.normalized(original) != nil)
        #expect(PDFCrossReferenceIntegrity.normalized(makePDF(orphan: true, indirectLength: true)) == nil)
    }

    @Test func hybridIncrementalAndBrokenFreeListsAreRejected() throws {
        let valid = try #require(PDFCrossReferenceIntegrity.normalized(makePDF(orphan: true)))
        let text = try #require(String(bytes: valid, encoding: .utf8))
        #expect(PDFCrossReferenceIntegrity.normalized(Data(
            text.replacingOccurrences(of: "/Root 1 0 R", with: "/Root 1 0 R /Prev 0").utf8
        )) == nil)
        #expect(PDFCrossReferenceIntegrity.normalized(Data(
            text.replacingOccurrences(of: "/Root 1 0 R", with: "/Root 1 0 R /XRefStm 0").utf8
        )) == nil)
        #expect(PDFCrossReferenceIntegrity.normalized(Data(
            text.replacingOccurrences(of: "0000000005 65535 f", with: "0000000000 65535 f").utf8
        )) == nil)
    }

    private func makePDF(orphan: Bool = false, reference: String = "", catalogExtra: String = "",
                         streamContent: String? = nil, trailerExtra: String = "",
                         indirectLength: Bool = false) -> Data {
        let content = streamContent ?? "0 0 0 rg 10 10 20 20 re f"
        let name = reference.isEmpty ? "" : "/Names \(reference)"
        let catalog = "<< /Type /Catalog /Pages 2 0 R \(name) \(catalogExtra) >>"
        let objects = [
            catalog,
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R >>",
            "<< /Length \(indirectLength ? "7 0 R" : String(content.utf8.count)) >>\nstream\n\(content)\nendstream",
        ]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        let count = objects.count + 1 + (orphan ? 1 : 0)
        pdf += "xref\n0 \(count)\n0000000000 65535 f \n"
        for offset in offsets {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        if orphan {
            pdf += "0000000000 00000 n \n"
        }
        pdf += "trailer\n<< /Size \(count) /Root 1 0 R \(trailerExtra) >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}
