import CoreGraphics
import CoreText
import Foundation
import ImageIO
import ScannerCore
import XCTest

final class PDFExporterTests: XCTestCase {
    func testSelectedLetterPaperCreatesLetterPagesWithoutChangingPageCountOrOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("letter.pdf")
        try PDFExporter(paperSize: .letter).export(
            pages: [page(red: 1, green: 0, blue: 0), page(red: 0, green: 0, blue: 1)], to: url
        )
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 2)
        for number in 1...2 {
            let pdfPage = try XCTUnwrap(document.page(at: number))
            let box = pdfPage.getBoxRect(.mediaBox)
            XCTAssertEqual(box.width, 612, accuracy: 0.001)
            XCTAssertEqual(box.height, 792, accuracy: 0.001)
            let pixel = try centerPixel(of: pdfPage)
            if number == 1 {
                XCTAssertGreaterThan(pixel.red, 240)
                XCTAssertLessThan(pixel.blue, 15)
            } else {
                XCTAssertGreaterThan(pixel.blue, 240)
                XCTAssertLessThan(pixel.red, 15)
            }
        }
    }

    func testPDFHasOnePortraitA4PagePerScanInOriginalOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document.pdf")
        let first = try page(red: 1, green: 0, blue: 0)
        let second = try page(red: 0, green: 0, blue: 1)

        try PDFExporter().export(pages: [first, second], to: url)

        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 2)
        for number in 1...2 {
            let pdfPage = try XCTUnwrap(document.page(at: number))
            let box = pdfPage.getBoxRect(.mediaBox)
            XCTAssertEqual(box.width, 595.276, accuracy: 0.01)
            XCTAssertEqual(box.height, 841.89, accuracy: 0.01)
            let pixel = try centerPixel(of: pdfPage)
            if number == 1 {
                XCTAssertGreaterThan(pixel.red, 240)
                XCTAssertLessThan(pixel.blue, 15)
            } else {
                XCTAssertGreaterThan(pixel.blue, 240)
                XCTAssertLessThan(pixel.red, 15)
            }
        }
    }

    func testExportRefusesToOverwriteExistingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("existing.pdf")
        let original = Data("Keep this user file".utf8)
        try original.write(to: url)

        XCTAssertThrowsError(try PDFExporter().export(pages: [page(red: 1, green: 1, blue: 1)], to: url)) {
            XCTAssertEqual($0 as? PDFExportError, .fileAlreadyExists)
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testEmptyOrUnreadablePagesDoNotCreatePDF() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document.pdf")
        let exporter = PDFExporter()

        XCTAssertThrowsError(try exporter.export(pages: [], to: url)) {
            XCTAssertEqual($0 as? PDFExportError, .noPages)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let valid = try page(red: 1, green: 1, blue: 1)
        XCTAssertThrowsError(try exporter.export(pages: [valid, ScannedPage(imageData: Data())], to: url)) {
            XCTAssertEqual($0 as? PDFExportError, .invalidPage(2))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDefaultCompressionShrinksNoisyScansWithoutReducingPixelDimensions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scan = try noisyDocumentPage()
        let compact = directory.appendingPathComponent("standard.pdf")
        let high = directory.appendingPathComponent("high-quality.pdf")
        let lossless = directory.appendingPathComponent("lossless.pdf")
        try PDFExporter().export(pages: [scan], to: compact)
        try PDFExporter(compression: .highQuality).export(pages: [scan], to: high)
        try PDFExporter(compression: .lossless).export(pages: [scan], to: lossless)

        let compactSize = try Data(contentsOf: compact).count
        let highSize = try Data(contentsOf: high).count
        let losslessSize = try Data(contentsOf: lossless).count
        XCTAssertLessThan(compactSize, losslessSize / 3)
        XCTAssertGreaterThan(highSize, compactSize)

        for url in [compact, high, lossless] {
            let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
            let pdfPage = try XCTUnwrap(document.page(at: 1))
            XCTAssertEqual(document.numberOfPages, 1)
            let images = try embeddedImages(in: pdfPage)
            XCTAssertEqual(images.count, 1)
            let image = try XCTUnwrap(images.first)
            XCTAssertEqual(image.width, 640)
            XCTAssertEqual(image.height, 905)
            XCTAssertEqual(image.filters.contains("DCTDecode"), url != lossless)
        }
    }

    func testJPEGCompressionCompositesTransparentPixelsOnWhitePaper() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("transparent.pdf")
        try PDFExporter().export(pages: [page(red: 0, green: 0, blue: 0, alpha: 0)], to: url)
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let pixel = try centerPixel(of: XCTUnwrap(document.page(at: 1)))
        XCTAssertGreaterThan(pixel.red, 240)
        XCTAssertGreaterThan(pixel.blue, 240)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func page(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) throws -> ScannedPage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 20, height: 28, bitsPerComponent: 8, bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 28))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return ScannedPage(imageData: data as Data)
    }

    private func noisyDocumentPage() throws -> ScannedPage {
        let width = 640
        let height = 905
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var seed: UInt64 = 123_456
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            pixels[offset] = UInt8(224 + ((seed >> 32) & 31))
            pixels[offset + 1] = UInt8(224 + ((seed >> 40) & 31))
            pixels[offset + 2] = UInt8(224 + ((seed >> 48) & 31))
            pixels[offset + 3] = 255
        }
        let text = NSAttributedString(string: "Document compression: keep fine text readable", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 19, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        for row in 0..<12 {
            context.textPosition = CGPoint(x: 25, y: 850 - row * 55)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return ScannedPage(imageData: data as Data)
    }

    private func embeddedImages(in page: CGPDFPage) throws -> [PDFImageInfo] {
        var resources: CGPDFDictionaryRef?
        var objects: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(page.dictionary), "Resources", &resources))
        XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(resources), "XObject", &objects))
        let collector = PDFImageCollector()
        CGPDFDictionaryApplyFunction(try XCTUnwrap(objects), { _, object, pointer in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let pointer else { return }
            guard let dictionary = CGPDFStreamGetDictionary(stream) else { return }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Image" else { return }
            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            CGPDFDictionaryGetInteger(dictionary, "Width", &width)
            CGPDFDictionaryGetInteger(dictionary, "Height", &height)
            var name: UnsafePointer<CChar>?
            var filters: [String] = []
            if CGPDFDictionaryGetName(dictionary, "Filter", &name), let name {
                filters.append(String(cString: name))
            } else {
                var array: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(dictionary, "Filter", &array), let array {
                    for index in 0..<CGPDFArrayGetCount(array) {
                        if CGPDFArrayGetName(array, index, &name), let name { filters.append(String(cString: name)) }
                    }
                }
            }
            Unmanaged<PDFImageCollector>.fromOpaque(pointer).takeUnretainedValue().images.append(
                PDFImageInfo(width: Int(width), height: Int(height), filters: filters)
            )
        }, Unmanaged.passUnretained(collector).toOpaque())
        return collector.images
    }

    private func centerPixel(of page: CGPDFPage) throws -> (red: UInt8, blue: UInt8) {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: 8, height: 8), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (4 * 8 + 4) * 4
        return (pixels[offset], pixels[offset + 2])
    }
}

private struct PDFImageInfo {
    let width: Int
    let height: Int
    let filters: [String]
}

private final class PDFImageCollector {
    var images: [PDFImageInfo] = []
}
