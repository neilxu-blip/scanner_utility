import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import ScannerCore
@testable import ScannerUtility
import XCTest

final class WorkflowExportTests: XCTestCase {
    func testPhotoCustomAndAdvancedExportNativeImageFormatsWithOriginalDimensions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try solidPage(width: 40, height: 60, red: 1, blue: 0)
        let cases: [(ScanWorkflowMode, ScanOutputFormat, String)] = [
            (.photo, .jpeg, "public.jpeg"), (.custom, .png, "public.png"), (.advanced, .tiff, "public.tiff"),
        ]
        for (mode, format, expectedType) in cases {
            var profile = DocumentSettings.defaults(for: mode)
            profile.outputFormat = format
            let url = directory.appendingPathComponent("\(mode.rawValue).\(format.fileExtension)")
            try ScanOutputExporter(mode: mode, profile: profile, general: GeneralSettings(), format: format)
                .export(pages: [page], to: url)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, expectedType)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 40)
            XCTAssertEqual(image.height, 60)
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertEqual(try XCTUnwrap(properties[kCGImagePropertyDPIWidth] as? Double), 300, accuracy: 0.1)
            XCTAssertEqual(try XCTUnwrap(properties[kCGImagePropertyDPIHeight] as? Double), 300, accuracy: 0.1)
        }
    }

    func testDocumentPDFUsesCustomPaperBoundsAndPreservesBatchOrder() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var profile = DocumentSettings()
        profile.scanOptions.paperSize = .custom
        profile.scanOptions.customWidthMillimeters = 100
        profile.scanOptions.customHeightMillimeters = 150
        profile.compression = .lossless
        let first = try solidPage(width: 40, height: 60, red: 1, blue: 0)
        let second = try solidPage(width: 40, height: 60, red: 0, blue: 1)
        let url = directory.appendingPathComponent("batch.pdf")
        try ScanOutputExporter(mode: .document, profile: profile, general: GeneralSettings(), format: .pdf)
            .export(pages: [first, second], to: url)
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 2)
        for number in 1...2 {
            let page = try XCTUnwrap(document.page(at: number))
            let bounds = page.getBoxRect(.mediaBox)
            XCTAssertEqual(bounds.width, 100 * 72 / 25.4, accuracy: 0.01)
            XCTAssertEqual(bounds.height, 150 * 72 / 25.4, accuracy: 0.01)
            let pixel = try centerPixel(page)
            if number == 1 {
                XCTAssertGreaterThan(pixel.red, 250)
                XCTAssertLessThan(pixel.blue, 5)
            } else {
                XCTAssertGreaterThan(pixel.blue, 250)
                XCTAssertLessThan(pixel.red, 5)
            }
        }
    }

    func testStitchExportsOneJoinedImageOrOnePDFWithExpandedCanvas() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try solidPage(width: 40, height: 60, red: 1, blue: 0)
        let second = try solidPage(width: 40, height: 60, red: 0, blue: 1)
        var profile = DocumentSettings.defaults(for: .stitch)
        profile.stitchDirection = .horizontal
        profile.stitchOverlap = 0.25
        let png = directory.appendingPathComponent("joined.png")
        try ScanOutputExporter(mode: .stitch, profile: profile, general: GeneralSettings(), format: .png)
            .export(pages: [first, second], to: png)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        let joined = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(joined.width, 70)
        XCTAssertEqual(joined.height, 60)

        let pdf = directory.appendingPathComponent("joined.pdf")
        try ScanOutputExporter(mode: .stitch, profile: profile, general: GeneralSettings(), format: .pdf)
            .export(pages: [first, second], to: pdf)
        let document = try XCTUnwrap(CGPDFDocument(pdf as CFURL))
        XCTAssertEqual(document.numberOfPages, 1)
        let bounds = try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(bounds.width, profile.scanOptions.pdfSize.width * 1.75, accuracy: 0.01)
        XCTAssertEqual(bounds.height, profile.scanOptions.pdfSize.height, accuracy: 0.01)

        let incomplete = directory.appendingPathComponent("incomplete.png")
        XCTAssertThrowsError(try ScanOutputExporter(mode: .stitch, profile: profile, general: GeneralSettings(), format: .png)
            .export(pages: [first], to: incomplete))
        XCTAssertFalse(FileManager.default.fileExists(atPath: incomplete.path))
    }

    func testManualImageExportsRefuseExistingDestinationAndPreserveBytes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try solidPage(width: 20, height: 30, red: 1, blue: 0)
        let existing = Data("Existing user file must remain intact".utf8)
        for format in [ScanOutputFormat.jpeg, .png, .tiff] {
            let url = directory.appendingPathComponent("existing.\(format.fileExtension)")
            try existing.write(to: url, options: .withoutOverwriting)
            var profile = DocumentSettings.defaults(for: .custom)
            profile.outputFormat = format
            XCTAssertThrowsError(try ScanOutputExporter(mode: .custom, profile: profile, general: GeneralSettings(), format: format)
                .export(pages: [page], to: url)) {
                XCTAssertEqual($0 as? PDFExportError, .fileAlreadyExists)
            }
            XCTAssertEqual(try Data(contentsOf: url), existing)
        }
    }

    func testOutgoingImageSizesCreateCopiesOnlyInConfiguredTemporaryFolder() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outgoingDirectory = directory.appendingPathComponent("outgoing", isDirectory: true)
        try FileManager.default.createDirectory(at: outgoingDirectory, withIntermediateDirectories: false)
        let original = directory.appendingPathComponent("original.png")
        let page = try solidPage(width: 1600, height: 800, red: 1, blue: 0)
        try page.imageData.write(to: original, options: .withoutOverwriting)
        let originalHash = SHA256.hash(data: try Data(contentsOf: original))
        var general = GeneralSettings()
        general.temporaryDirectory = outgoingDirectory
        for size in [SendImageSize.small, .medium, .large] {
            general.sendImageSize = size
            let copy = try OutgoingScanImage.url(for: original, general: general)
            XCTAssertNotEqual(copy, original)
            XCTAssertEqual(copy.deletingLastPathComponent().standardizedFileURL, outgoingDirectory.standardizedFileURL)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(copy as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let maximum = try XCTUnwrap(size.maxPixelDimension)
            XCTAssertEqual(image.width, maximum)
            XCTAssertEqual(image.height, maximum / 2)
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: original)), originalHash)
        }
        general.sendImageSize = .original
        XCTAssertEqual(try OutgoingScanImage.url(for: original, general: general), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: outgoingDirectory, includingPropertiesForKeys: nil).count, 3)
    }

    func testOutgoingPDFPassesThroughUnchangedAndMissingTemporaryFolderDoesNotAlterImage() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = directory.appendingPathComponent("document.pdf")
        let image = directory.appendingPathComponent("image.png")
        let page = try solidPage(width: 40, height: 60, red: 1, blue: 0)
        try page.imageData.write(to: image, options: .withoutOverwriting)
        try ScanOutputExporter(mode: .document, profile: DocumentSettings(), general: GeneralSettings(), format: .pdf)
            .export(pages: [page], to: pdf)
        let pdfHash = SHA256.hash(data: try Data(contentsOf: pdf))
        var general = GeneralSettings()
        general.sendImageSize = .small
        general.temporaryDirectory = directory.appendingPathComponent("missing", isDirectory: true)
        XCTAssertEqual(try OutgoingScanImage.url(for: pdf, general: general), pdf)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: pdf)), pdfHash)
        XCTAssertThrowsError(try OutgoingScanImage.url(for: image, general: general))
        XCTAssertEqual(try Data(contentsOf: image), page.imageData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: general.temporaryDirectory.path))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkflowExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func solidPage(width: Int, height: Int, red: CGFloat, blue: CGFloat) throws -> ScannedPage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [
            kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300,
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return ScannedPage(imageData: data as Data)
    }

    private func centerPixel(_ page: CGPDFPage) throws -> (red: UInt8, blue: UInt8) {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 20 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let bounds = page.getBoxRect(.mediaBox)
        context.scaleBy(x: 20 / bounds.width, y: 20 / bounds.height)
        context.drawPDFPage(page)
        let pointer = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (10 * 20 + 10) * 4
        return (pointer[offset], pointer[offset + 2])
    }
}
