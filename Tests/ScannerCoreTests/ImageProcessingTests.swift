import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import PDFKit
import ScannerCore
import XCTest

final class ImageProcessingTests: XCTestCase {
    func testDisabledCorrectionsPreserveOriginalBytesAndIdentity() throws {
        let page = try textPage()
        let result = try ImageProcessor().process(page)
        XCTAssertEqual(result.id, page.id)
        XCTAssertEqual(result.imageData, page.imageData)
    }

    func testBrightnessAndBlackWhiteProduceBinaryPixelsWithoutResizing() throws {
        let page = try bitmap(width: 120, height: 80) { context in
            context.setFillColor(CGColor(gray: 0.25, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
            context.setFillColor(CGColor(gray: 0.75, alpha: 1))
            context.fill(CGRect(x: 60, y: 0, width: 60, height: 80))
        }
        let result = try ImageProcessor(options: .init(blackAndWhite: true)).process(page)
        let image = try decoded(result)
        XCTAssertEqual(result.id, page.id)
        XCTAssertEqual(image.width, 120)
        XCTAssertEqual(image.height, 80)
        XCTAssertLessThan(try pixel(image, x: 20, y: 40), 5)
        XCTAssertGreaterThan(try pixel(image, x: 100, y: 40), 250)
        let bright = try decoded(ImageProcessor(options: .init(brightness: 0.3)).process(page))
        XCTAssertGreaterThan(try pixel(bright, x: 20, y: 40), try pixel(decoded(page), x: 20, y: 40) + 30)
    }

    func testShowThroughCorrectionLightensFaintBackgroundWhileRetainingDarkText() throws {
        let page = try bitmap(width: 200, height: 200) { context in
            context.setFillColor(CGColor(gray: 0.75, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 80, y: 80, width: 40, height: 40))
        }
        let corrected = try decoded(ImageProcessor(options: .init(reduceShowThrough: true)).process(page))
        XCTAssertGreaterThan(try pixel(corrected, x: 20, y: 20), try pixel(decoded(page), x: 20, y: 20) + 10)
        XCTAssertLessThan(try pixel(corrected, x: 100, y: 100), 10)
    }

    func testGutterCorrectionReducesBroadShadowAndRetainsDarkInk() throws {
        let page = try bitmap(width: 400, height: 300) { context in
            context.setFillColor(CGColor(gray: 0.6, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 190, y: 145, width: 20, height: 10))
        }
        let corrected = try decoded(ImageProcessor(options: .init(reduceGutterShadow: true)).process(page))
        XCTAssertGreaterThan(try pixel(corrected, x: 30, y: 30), 235)
        XCTAssertLessThan(try pixel(corrected, x: 200, y: 150), 20)
    }

    func testAutoCropRemovesConfidentDocumentBorderButKeepsUnrecognizedImage() throws {
        let bordered = try bitmap(width: 900, height: 1_200) { context in
            context.setFillColor(CGColor(gray: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1_200))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 90, y: 120, width: 720, height: 960))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 200, y: 700, width: 500, height: 10))
        }
        let cropped = try decoded(ImageProcessor(options: .init(autoCrop: true)).process(bordered))
        XCTAssertLessThan(cropped.width, 830)
        XCTAssertGreaterThan(cropped.width, 650)
        XCTAssertLessThan(cropped.height, 1_100)
        let blank = try bitmap(width: 120, height: 180) { _ in }
        let unchanged = try decoded(ImageProcessor(options: .init(autoCrop: true, deskew: true)).process(blank))
        XCTAssertEqual(unchanged.width, 120)
        XCTAssertEqual(unchanged.height, 180)
    }

    func testLocalOCRRecognizesTextAndClassifiesTextRichPagesAsDocuments() throws {
        let page = try textPage()
        let text = try ScanTextRecognizer.recognize(page)
        XCTAssertTrue(text.map(\.text).joined(separator: " ").contains("SCANNER"))
        XCTAssertTrue(text.allSatisfy { $0.bounds.minX >= 0 && $0.bounds.maxX <= 1 && $0.bounds.minY >= 0 && $0.bounds.maxY <= 1 })
        switch try ImageProcessor.classify(page) {
        case .document: break
        case .photo: XCTFail("A clear multi-line printed page should be recognized as a document.")
        }
        let blank = try bitmap(width: 200, height: 300) { _ in }
        switch try ImageProcessor.classify(blank) {
        case .photo: break
        case .document: XCTFail("A page without recognized text should use the photo fallback.")
        }
    }

    func testSearchablePDFContainsTextInImageBoundsAndKeepsVisiblePixelsUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try textPage()
        let plain = directory.appendingPathComponent("plain.pdf")
        let searchable = directory.appendingPathComponent("searchable.pdf")
        let size = CGSize(width: 612, height: 792)
        try PDFExporter(compression: .lossless, pageSize: size).export(pages: [page], to: plain)
        try PDFExporter(compression: .lossless, searchable: true, pageSize: size).export(pages: [page, page], to: searchable)
        let document = try XCTUnwrap(PDFDocument(url: searchable))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(try XCTUnwrap(document.string).contains("SCANNER"))
        let pdfPage = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(pdfPage.bounds(for: .mediaBox), CGRect(origin: .zero, size: size))
        let selection = try XCTUnwrap(document.findString("SCANNER", withOptions: []).first)
        let bounds = selection.bounds(for: pdfPage)
        XCTAssertTrue(pdfPage.bounds(for: .mediaBox).contains(bounds))
        XCTAssertGreaterThan(bounds.width, 10)
        XCTAssertGreaterThan(bounds.height, 5)
        XCTAssertEqual(try renderedPDF(plain), try renderedPDF(searchable))
        let plainDocument = try XCTUnwrap(PDFDocument(url: plain))
        XCTAssertTrue((plainDocument.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testProcessingReportsInvalidInputWithoutCreatingAnImage() {
        XCTAssertThrowsError(try ImageProcessor(options: .init(sharpen: true)).process(ScannedPage(imageData: Data())))
    }

    func testAutoRotateRestoresClearPrintedTextFromEveryQuarterTurn() throws {
        let upright = try decoded(textPage())
        for orientation: CGImagePropertyOrientation in [.up, .right, .down, .left] {
            let rotated = CIImage(cgImage: upright).oriented(orientation)
            let image = try XCTUnwrap(CIContext().createCGImage(rotated, from: rotated.extent))
            let result = try ImageProcessor(options: .init(autoRotate: true)).process(encoded(image))
            let restored = try decoded(result)
            XCTAssertEqual(restored.width, upright.width, "Input orientation \(orientation.rawValue)")
            XCTAssertEqual(restored.height, upright.height, "Input orientation \(orientation.rawValue)")
            XCTAssertLessThan(try meanPixelDifference(restored, upright), 1, "Text must face upright, not merely remain readable to OCR.")
        }
    }

    func testAutoRotateUsesSelectedChineseLanguageForUpsideDownText() throws {
        let upright = try decoded(textPage(rows: [
            "这是扫描工具的中文测试文档", "本地文字识别不需要网络连接",
            "多页扫描保留正确的页面顺序", "请把文档旋转到正常阅读方向"
        ], fontName: "PingFangSC-Regular"))
        let rotated = CIImage(cgImage: upright).oriented(.down)
        let image = try XCTUnwrap(CIContext().createCGImage(rotated, from: rotated.extent))
        let page = try ImageProcessor(options: .init(autoRotate: true), recognitionLanguages: ["zh-Hans"])
            .process(encoded(image))
        XCTAssertLessThan(try meanPixelDifference(decoded(page), upright), 1)
        XCTAssertTrue(try ScanTextRecognizer.recognize(page, languages: ["zh-Hans"])
            .map(\.text).joined().contains("测试文档"))
    }

    func testCanceledTaskDoesNotStartNativeProcessing() async throws {
        let page = try textPage()
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ImageProcessor(options: .init(autoRotate: true)).process(page)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        let canceled = await task.value
        XCTAssertTrue(canceled)
    }

    func testDeskewExpandsCanvasInsteadOfDiscardingImageCorners() throws {
        let skewed = try bitmap(width: 900, height: 1_200) { context in
            context.setFillColor(CGColor(gray: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1_200))
            context.translateBy(x: 450, y: 600)
            context.rotate(by: 5 * .pi / 180)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: -330, y: -470, width: 660, height: 940))
        }
        let corrected = try decoded(ImageProcessor(options: .init(deskew: true)).process(skewed))
        XCTAssertGreaterThan(corrected.width, 900)
        XCTAssertGreaterThan(corrected.height, 1_200)
    }

    func testMoireReductionSoftensPixelPatternAndGammaChangesMidtones() throws {
        let pattern = try bitmap(width: 200, height: 200) { context in
            for x in 0..<200 {
                context.setFillColor(CGColor(gray: x.isMultiple(of: 2) ? 0.2 : 0.8, alpha: 1))
                context.fill(CGRect(x: x, y: 0, width: 1, height: 200))
            }
        }
        let corrected = try decoded(ImageProcessor(options: .init(reduceMoire: true)).process(pattern))
        let before = try decoded(pattern)
        let inputDifference = abs(try pixel(before, x: 100, y: 100) - pixel(before, x: 101, y: 100))
        let outputDifference = abs(try pixel(corrected, x: 100, y: 100) - pixel(corrected, x: 101, y: 100))
        XCTAssertLessThan(outputDifference, inputDifference / 2)
        let gray = try bitmap(width: 50, height: 50) { context in
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        let gamma = try decoded(ImageProcessor(options: .init(gamma: 2)).process(gray))
        XCTAssertLessThan(try pixel(gamma, x: 25, y: 25), try pixel(decoded(gray), x: 25, y: 25) - 20)
    }

    func testCorrectedImageRetainsAcquisitionResolutionMetadata() throws {
        let page = try textPage()
        let corrected = try ImageProcessor(options: .init(sharpen: true, contrast: 0.1)).process(page)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(corrected.imageData as CFData, nil))
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(try XCTUnwrap(metadata[kCGImagePropertyDPIWidth] as? Double), 300, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(metadata[kCGImagePropertyDPIHeight] as? Double), 300, accuracy: 0.1)
    }

    private func textPage(rows: [String]? = nil, fontName: String = "Helvetica") throws -> ScannedPage {
        try bitmap(width: 1_200, height: 1_600) { context in
            let rows = rows ?? ["SCANNER UTILITY TEST DOCUMENT", "Clear printed text stays searchable", "Native local recognition works offline", "MULTIPLE PAGES KEEP THEIR ORDER"]
            for (index, value) in rows.enumerated() {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName as CFString, 48, nil),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
                ]))
                context.textPosition = CGPoint(x: 65, y: 1_360 - index * 180)
                CTLineDraw(line, context)
            }
        }
    }

    private func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) throws -> ScannedPage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        return try encoded(XCTUnwrap(context.makeImage()))
    }

    private func encoded(_ image: CGImage) throws -> ScannedPage {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return ScannedPage(imageData: data as Data)
    }

    private func decoded(_ page: ScannedPage) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(page.imageData as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> Int {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Int(try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)[(y * image.width + x) * 4])
    }

    private func meanPixelDifference(_ image: CGImage, _ reference: CGImage) throws -> Double {
        guard image.width == reference.width, image.height == reference.height else { return .infinity }
        func raster(_ image: CGImage) throws -> Data {
            let context = try XCTUnwrap(CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
        }
        let values = try raster(image)
        let expected = try raster(reference)
        let difference = zip(values, expected).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(difference) / Double(values.count)
    }

    private func renderedPDF(_ url: URL) throws -> Data {
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 306, height: 396, bitsPerComponent: 8, bytesPerRow: 306 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: 306, height: 396), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return Data(bytes: try XCTUnwrap(context.data), count: 306 * 396 * 4)
    }
}
