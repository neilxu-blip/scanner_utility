import Foundation
import ScannerCore
import XCTest

final class DocumentScanOptionsTests: XCTestCase {
    func testDefaultsAndPersistedSelectionsRoundTrip() throws {
        let defaults = DocumentScanOptions()
        XCTAssertEqual(defaults.colorMode, .color)
        XCTAssertEqual(defaults.paperSize, .a4)
        XCTAssertEqual(defaults.resolution, .dpi300)

        let selected = DocumentScanOptions(colorMode: .grayscale, paperSize: .letter, resolution: .dpi600)
        let restored = try JSONDecoder().decode(DocumentScanOptions.self, from: JSONEncoder().encode(selected))
        XCTAssertEqual(restored, selected)
    }

    func testPaperGeometryUsesPortraitDimensionsAndExplicitJISB5() {
        XCTAssertEqual(ScanPaperSize.letter.pdfSize.width, 612, accuracy: 0.000_001)
        XCTAssertEqual(ScanPaperSize.letter.pdfSize.height, 792, accuracy: 0.000_001)
        XCTAssertEqual(ScanPaperSize.a5.widthMillimeters, 148)
        XCTAssertEqual(ScanPaperSize.a5.heightMillimeters, 210)
        XCTAssertEqual(ScanPaperSize.b5.widthMillimeters, 182)
        XCTAssertEqual(ScanPaperSize.b5.heightMillimeters, 257)
        for paper in ScanPaperSize.allCases {
            XCTAssertLessThan(paper.pdfSize.width, paper.pdfSize.height)
            XCTAssertEqual(paper.pdfSize.width / paper.pdfSize.height,
                           paper.widthMillimeters / paper.heightMillimeters, accuracy: 0.000_001)
        }
    }
}
