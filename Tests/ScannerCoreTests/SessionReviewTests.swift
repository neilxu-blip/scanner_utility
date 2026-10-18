import CoreGraphics
import Foundation
import ImageIO
import ScannerCore
import XCTest

@MainActor
final class SessionReviewTests: XCTestCase {
    func testReviewEditsOnlyTheReadyBatchAndDiscardRestoresAnIdleSession() async throws {
        let first = ScannedPage(imageData: Data([1]))
        let second = ScannedPage(imageData: Data([2]))
        let session = DocumentSession(backend: SequenceBackend(pages: [first, second]))
        session.start()
        session.removePage(id: first.id)
        try await waitReady(session)
        session.scanNext()
        try await waitReady(session)
        session.movePage(id: second.id, by: -1)
        XCTAssertEqual(session.pages.map(\.id), [second.id, first.id])
        let edited = ScannedPage(id: first.id, imageData: Data([3]))
        session.replacePage(id: first.id, with: edited)
        XCTAssertEqual(session.pages.last?.imageData, Data([3]))
        XCTAssertEqual(first.imageData, Data([1]))
        session.movePage(id: first.id, by: Int.max)
        XCTAssertEqual(session.pages.map(\.id), [second.id, first.id])
        session.removePage(id: second.id)
        XCTAssertEqual(session.pages.map(\.id), [first.id])
        session.discard()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertTrue(session.pages.isEmpty)
        XCTAssertNil(session.errorMessage)
    }

    func testExportOverrideFailureRetainsImagesAndSuccessfulRetryUsesChosenExporter() async throws {
        let original = ScannedPage(imageData: Data([1]))
        let session = DocumentSession(backend: SequenceBackend(pages: [original]))
        session.start()
        try await waitReady(session)
        await session.export(to: URL(fileURLWithPath: "/unused/output.png"), exporter: ReviewExporter(fails: true))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.pages.map(\.id), [original.id])
        XCTAssertNotNil(session.errorMessage)
        await session.export(to: URL(fileURLWithPath: "/unused/output.png"), exporter: ReviewExporter(fails: false))
        XCTAssertEqual(session.phase, .saved)
        XCTAssertEqual(session.savedURL?.pathExtension, "png")
        XCTAssertEqual(session.pages.first?.imageData, original.imageData)
    }

    func testRotationPreservesPageIdentityAndSwapsImageDimensions() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 60, bitsPerComponent: 8,
            bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = ScannedPage(imageData: data as Data)
        let rotated = try ScanPageEditing.rotateClockwise(original)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(rotated.imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(rotated.id, original.id)
        XCTAssertEqual(image.width, 60)
        XCTAssertEqual(image.height, 40)
        XCTAssertEqual(original.imageData, data as Data)
    }

    private func waitReady(_ session: DocumentSession) async throws {
        for _ in 0..<100 {
            if session.phase == .ready { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Session did not reach review state")
    }
}

private actor SequenceBackend: ScannerBackend {
    nonisolated let displayName = "Review fixture"
    let pages: [ScannedPage]
    init(pages: [ScannedPage]) { self.pages = pages }
    func scanPage(number: Int, progress: @escaping @Sendable (Double) async -> Void) async throws -> ScannedPage {
        pages[number - 1]
    }
}

private struct ReviewExporter: PDFExporting {
    let fails: Bool
    func export(pages: [ScannedPage], to url: URL) throws {
        if fails { throw CocoaError(.fileWriteFileExists) }
    }
}
