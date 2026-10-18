import Foundation
import ImageIO
import ScannerCore
import XCTest

final class MockScannerBackendTests: XCTestCase {
    func testMockProducesDeterministicReadablePNGsWithCompleteProgress() async throws {
        let backend = MockScannerBackend()
        let recorder = ProgressRecorder()
        let first = try await backend.scanPage(number: 1) { await recorder.record($0) }
        let second = try await backend.scanPage(number: 1) { _ in }
        let values = await recorder.values

        XCTAssertEqual(first.imageData, second.imageData)
        XCTAssertNotEqual(first.id, second.id)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(first.imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1_240)
        XCTAssertEqual(image.height, 1_754)
        XCTAssertEqual(values.first, 0)
        XCTAssertEqual(values.last, 1)
        XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    func testMockScanCooperatesWithCancellation() async throws {
        let task = Task { try await MockScannerBackend().scanPage(number: 1) { _ in } }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation to stop the mock scan")
        } catch is CancellationError {
            // Expected: a cancelled acquisition must not produce a completed page.
        }
    }

    func testMockUsesSelectedPaperAspectRatioAndGrayscalePixels() async throws {
        let options = DocumentScanOptions(colorMode: .grayscale, paperSize: .letter, resolution: .dpi600)
        let page = try await MockScannerBackend(options: options).scanPage(number: 2) { _ in }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(page.imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.colorSpace?.model, .monochrome)
        XCTAssertEqual(Double(image.width) / Double(image.height), 8.5 / 11, accuracy: 0.000_5)
    }
}

private actor ProgressRecorder {
    private(set) var values: [Double] = []

    func record(_ value: Double) {
        values.append(value)
    }
}
