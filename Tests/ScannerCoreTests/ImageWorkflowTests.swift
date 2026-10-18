import CoreGraphics
import Foundation
import ImageIO
import ScannerCore
import XCTest

final class ImageWorkflowTests: XCTestCase {
    func testImageFormatsPreservePixelDimensionsResolutionAndNativeType() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let page = try solidPage(width: 24, height: 36, red: 1, blue: 0)
        for (format, type) in [(ScanOutputFormat.jpeg, "public.jpeg"), (.png, "public.png"), (.tiff, "public.tiff")] {
            let url = folder.appendingPathComponent("image.\(format.fileExtension)")
            try ImageExporter(format: format).export(pages: [page], to: url)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, type)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 24)
            XCTAssertEqual(image.height, 36)
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertEqual(try XCTUnwrap(properties[kCGImagePropertyDPIWidth] as? Double), 300, accuracy: 0.1)
            XCTAssertEqual(try XCTUnwrap(properties[kCGImagePropertyDPIHeight] as? Double), 300, accuracy: 0.1)
        }
    }

    func testJPEGCompositesTransparencyOnWhiteAndExportPreservesExistingFiles() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("transparent.jpg")
        let page = try solidPage(width: 8, height: 8, red: 0, blue: 0, alpha: 0)
        try ImageExporter(format: .jpeg).export(pages: [page], to: url)
        let original = try Data(contentsOf: url)
        let pixels = try imagePixels(ScannedPage(imageData: original))
        XCTAssertGreaterThan(pixels.bytes[0], 245)
        XCTAssertGreaterThan(pixels.bytes[2], 245)
        XCTAssertThrowsError(try ImageExporter(format: .png).export(pages: [page], to: url)) {
            XCTAssertEqual($0 as? PDFExportError, .fileAlreadyExists)
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testImageExporterRejectsBatchesAndBadInputsBeforeCreatingOutput() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("output.png")
        let page = try solidPage(width: 8, height: 8, red: 1, blue: 0)
        for pages in [[], [page, page]] {
            XCTAssertThrowsError(try ImageExporter(format: .png).export(pages: pages, to: url)) {
                XCTAssertEqual($0 as? ImageExportError, .singlePageRequired)
            }
        }
        XCTAssertThrowsError(try ImageExporter(format: .pdf).export(pages: [page], to: url)) {
            XCTAssertEqual($0 as? ImageExportError, .unsupportedFormat)
        }
        XCTAssertThrowsError(try ImageExporter(format: .jpeg, jpegQuality: .nan).export(pages: [page], to: url))
        XCTAssertThrowsError(try ImageExporter(format: .png).export(pages: [ScannedPage(imageData: Data())], to: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testHorizontalStitchPreservesOrderAndFeathersOnlyOverlap() throws {
        let first = try solidPage(width: 8, height: 4, red: 1, blue: 0)
        let second = try solidPage(width: 8, height: 4, red: 0, blue: 1)
        let result = try ImageStitcher.stitch(first, second, overlap: 0.25)
        let pixels = try imagePixels(result)
        XCTAssertEqual(pixels.width, 14)
        XCTAssertEqual(pixels.height, 4)
        XCTAssertGreaterThan(pixels.bytes[0], 250)
        XCTAssertLessThan(pixels.bytes[2], 5)
        let seam = 6 * 4
        XCTAssertGreaterThan(pixels.bytes[seam], pixels.bytes[seam + 2])
        XCTAssertLessThan(pixels.bytes[seam + 4], pixels.bytes[seam + 6])
        let last = 13 * 4
        XCTAssertLessThan(pixels.bytes[last], 5)
        XCTAssertGreaterThan(pixels.bytes[last + 2], 250)
    }

    func testVerticalStitchPlacesFirstAboveSecondAndAllowsZeroOverlap() throws {
        let first = try solidPage(width: 4, height: 8, red: 1, blue: 0)
        let second = try solidPage(width: 4, height: 8, red: 0, blue: 1)
        let result = try ImageStitcher.stitch(first, second, direction: .vertical, overlap: 0)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 16)
        // CGImage cropping uses image row coordinates, with the first row at
        // the top, so this verifies visual order rather than only bitmap order.
        let top = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: 4, height: 1)))
        let bottom = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 15, width: 4, height: 1)))
        let topBytes = try pixels(top)
        let bottomBytes = try pixels(bottom)
        XCTAssertGreaterThan(topBytes[0], 250)
        XCTAssertLessThan(topBytes[2], 5)
        XCTAssertGreaterThan(bottomBytes[2], 250)
        XCTAssertLessThan(bottomBytes[0], 5)
    }

    func testStitchRejectsInvalidOverlapIncompleteImagesAndMismatchedSizes() throws {
        let page = try solidPage(width: 8, height: 8, red: 1, blue: 0)
        for overlap in [-0.1, 0.51, .infinity, .nan] {
            XCTAssertThrowsError(try ImageStitcher.stitch(page, page, overlap: overlap)) {
                XCTAssertEqual($0 as? ImageStitchError, .invalidOverlap)
            }
        }
        let other = try solidPage(width: 8, height: 4, red: 0, blue: 1)
        XCTAssertThrowsError(try ImageStitcher.stitch(page, other)) {
            XCTAssertEqual($0 as? ImageStitchError, .incompatibleDimensions)
        }
        XCTAssertThrowsError(try ImageStitcher.stitch(page, ScannedPage(imageData: Data()))) {
            XCTAssertEqual($0 as? ImageStitchError, .invalidImage)
        }
    }

    func testCanceledStitchDoesNotProduceAnImage() async throws {
        let page = try solidPage(width: 8, height: 8, red: 1, blue: 0)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImageStitcher.stitch(page, page)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cooperative cancellation")
        } catch is CancellationError {}
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func solidPage(width: Int, height: Int, red: CGFloat, blue: CGFloat, alpha: CGFloat = 1) throws -> ScannedPage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [
            kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return ScannedPage(imageData: data as Data)
    }

    private func imagePixels(_ page: ScannedPage) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(page.imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height, try pixels(image))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pointer = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: image.width * image.height * 4))
    }
}
