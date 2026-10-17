import Foundation
import ScannerCore
import XCTest

@MainActor
final class DocumentSessionTests: XCTestCase {
    func testPagesAccumulateInOrderWithoutExportUntilExit() async throws {
        let backend = ControlledScanner()
        let exporter = RecordingExporter()
        let session = DocumentSession(backend: backend, exporter: exporter)
        let first = ScannedPage(imageData: Data([1]))
        let second = ScannedPage(imageData: Data([2]))

        session.start()
        try await waitUntil { await backend.requestCount == 1 }
        await backend.complete(0, with: first)
        try await waitUntil { session.phase == .ready }
        XCTAssertEqual(session.pages.map(\.id), [first.id])
        XCTAssertTrue(exporter.exports.isEmpty)

        session.scanNext()
        try await waitUntil { await backend.requestCount == 2 }
        XCTAssertEqual(session.pages.map(\.id), [first.id])
        await backend.complete(1, with: second)
        try await waitUntil { session.phase == .ready }
        XCTAssertEqual(session.pages.map(\.id), [first.id, second.id])
        XCTAssertTrue(exporter.exports.isEmpty)
        let numbers = await backend.pageNumbers
        XCTAssertEqual(numbers, [1, 2])

        let url = URL(fileURLWithPath: "/unused/document.pdf")
        await session.export(to: url)
        XCTAssertEqual(session.phase, .saved)
        XCTAssertEqual(session.savedURL, url)
        XCTAssertEqual(exporter.exports.map { $0.pages.map(\.id) }, [[first.id, second.id]])

        session.start()
        XCTAssertEqual(session.phase, .scanning)
        XCTAssertTrue(session.pages.isEmpty)
        XCTAssertNil(session.savedURL)
        try await waitUntil { await backend.requestCount == 3 }
        session.cancelScan()
        await backend.complete(2, with: first)
    }

    func testFailedExportRetainsPagesAndAllowsRetry() async throws {
        let backend = ControlledScanner()
        let exporter = RecordingExporter(failuresRemaining: 1)
        let session = DocumentSession(backend: backend, exporter: exporter)
        let page = ScannedPage(imageData: Data([1]))
        session.start()
        try await waitUntil { await backend.requestCount == 1 }
        await backend.complete(0, with: page)
        try await waitUntil { session.phase == .ready }

        let url = URL(fileURLWithPath: "/unused/document.pdf")
        await session.export(to: url)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.pages.map(\.id), [page.id])
        XCTAssertNotNil(session.errorMessage)
        XCTAssertNil(session.savedURL)

        await session.export(to: url)
        XCTAssertEqual(session.phase, .saved)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(exporter.exports.count, 2)
    }

    func testCancellationPreservesCompletedPagesAndRejectsLateResultAndProgress() async throws {
        let backend = ControlledScanner()
        let session = DocumentSession(backend: backend)
        let first = ScannedPage(imageData: Data([1]))
        let stale = ScannedPage(imageData: Data([2]))
        let next = ScannedPage(imageData: Data([3]))

        session.start()
        try await waitUntil { await backend.requestCount == 1 }
        await backend.complete(0, with: first)
        try await waitUntil { session.phase == .ready }

        session.scanNext()
        try await waitUntil { await backend.requestCount == 2 }
        await backend.sendProgress(0.8, for: 1)
        XCTAssertEqual(session.progress, 0.8)
        session.cancelScan()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.pages.map(\.id), [first.id])

        session.scanNext()
        try await waitUntil { await backend.requestCount == 3 }
        await backend.sendProgress(0.1, for: 2)
        await backend.sendProgress(1, for: 1)
        await backend.complete(1, with: stale)
        await Task.yield()
        XCTAssertEqual(session.phase, .scanning)
        XCTAssertEqual(session.progress, 0.1)
        XCTAssertEqual(session.pages.map(\.id), [first.id])

        await backend.complete(2, with: next)
        try await waitUntil { session.phase == .ready }
        XCTAssertEqual(session.pages.map(\.id), [first.id, next.id])
    }

    func testCancelledFirstScanCanRestartWithoutAcceptingOldPage() async throws {
        let backend = ControlledScanner()
        let session = DocumentSession(backend: backend)
        session.start()
        try await waitUntil { await backend.requestCount == 1 }
        session.cancelScan()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertTrue(session.pages.isEmpty)

        session.start()
        try await waitUntil { await backend.requestCount == 2 }
        await backend.complete(0, with: ScannedPage(imageData: Data([1])))
        let current = ScannedPage(imageData: Data([2]))
        await backend.complete(1, with: current)
        try await waitUntil { session.phase == .ready }
        XCTAssertEqual(session.pages.map(\.id), [current.id])
    }

    func testStateGuardsPreventOverlappingScansAndEarlyExport() async throws {
        let backend = ControlledScanner()
        let exporter = RecordingExporter()
        let session = DocumentSession(backend: backend, exporter: exporter)
        let url = URL(fileURLWithPath: "/unused/document.pdf")
        session.scanNext()
        session.cancelScan()
        await session.export(to: url)
        XCTAssertEqual(session.phase, .idle)

        session.start()
        session.start()
        session.scanNext()
        await session.export(to: url)
        try await waitUntil { await backend.requestCount == 1 }
        let requestCount = await backend.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(exporter.exports.isEmpty)

        await backend.complete(0, with: ScannedPage(imageData: Data([1])))
        try await waitUntil { session.phase == .ready }
        session.start()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.pages.count, 1)
    }

    func testScanFailureRetainsPagesAndProgressIsFiniteMonotonicAndClamped() async throws {
        let backend = ControlledScanner()
        let session = DocumentSession(backend: backend)
        session.start()
        try await waitUntil { await backend.requestCount == 1 }
        await backend.fail(0)
        try await waitUntil { session.phase == .idle }
        XCTAssertNotNil(session.errorMessage)
        session.clearError()
        XCTAssertNil(session.errorMessage)

        session.start()
        try await waitUntil { await backend.requestCount == 2 }
        await backend.sendProgress(-1, for: 1)
        XCTAssertEqual(session.progress, 0)
        await backend.sendProgress(0.6, for: 1)
        await backend.sendProgress(.nan, for: 1)
        await backend.sendProgress(0.2, for: 1)
        XCTAssertEqual(session.progress, 0.6)
        await backend.sendProgress(2, for: 1)
        XCTAssertEqual(session.progress, 1)
        let first = ScannedPage(imageData: Data([1]))
        await backend.complete(1, with: first)
        try await waitUntil { session.phase == .ready }

        session.scanNext()
        try await waitUntil { await backend.requestCount == 3 }
        await backend.fail(2)
        try await waitUntil { session.phase == .ready }
        XCTAssertEqual(session.pages.map(\.id), [first.id])
        XCTAssertNotNil(session.errorMessage)
    }

    func testWarmupEndsOnAcquisitionAndResetsForTheNextPage() async throws {
        let backend = StatusScanner()
        let session = DocumentSession(backend: backend)
        session.start()
        try await waitUntil { await backend.requestCount == 1 }
        XCTAssertEqual(session.scanStatus, .warmingUp)

        await backend.send(.scanning(progress: nil))
        XCTAssertEqual(session.scanStatus, .scanning(progress: nil))
        await backend.send(.scanning(progress: 0))
        XCTAssertEqual(session.scanStatus, .scanning(progress: 0))
        await backend.send(.scanning(progress: 0.25))
        await backend.send(.warmingUp)
        await backend.send(.scanning(progress: nil))
        XCTAssertEqual(session.scanStatus, .scanning(progress: 0.25))
        XCTAssertEqual(session.progress, 0.25)

        await backend.complete()
        try await waitUntil { session.phase == .ready }
        session.scanNext()
        try await waitUntil { await backend.requestCount == 2 }
        XCTAssertEqual(session.scanStatus, .warmingUp)
        XCTAssertEqual(session.progress, 0)
        session.cancelScan()
        await backend.send(.scanning(progress: 0.75))
        await backend.complete()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.pages.count, 1)
        XCTAssertEqual(session.progress, 0)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for document session state")
        throw TestError.timeout
    }
}

private actor StatusScanner: ScannerBackend {
    nonisolated let displayName = "Status Scanner"
    private(set) var requestCount = 0
    private var callback: (@Sendable (ScannerStatus) async -> Void)?
    private var continuation: CheckedContinuation<ScannedPage, any Error>?

    func scanPage(number: Int, progress: @escaping @Sendable (Double) async -> Void) async throws -> ScannedPage {
        try await scanPage(number: number, status: { value in
            if case .scanning(let fraction) = value, let fraction { await progress(fraction) }
        })
    }

    func scanPage(number: Int, status: @escaping @Sendable (ScannerStatus) async -> Void) async throws -> ScannedPage {
        callback = status
        return try await withCheckedThrowingContinuation {
            continuation = $0
            requestCount += 1
        }
    }

    func send(_ status: ScannerStatus) async { await callback?(status) }

    func complete() {
        continuation?.resume(returning: ScannedPage(imageData: Data([1])))
        continuation = nil
    }
}

private actor ControlledScanner: ScannerBackend {
    nonisolated let displayName = "Controlled Scanner"

    private struct Request {
        let number: Int
        let progress: @Sendable (Double) async -> Void
        var continuation: CheckedContinuation<ScannedPage, any Error>?
    }

    private var requests: [Request] = []
    var requestCount: Int { requests.count }
    var pageNumbers: [Int] { requests.map(\.number) }

    func scanPage(number: Int, progress: @escaping @Sendable (Double) async -> Void) async throws -> ScannedPage {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(number: number, progress: progress, continuation: continuation))
        }
    }

    func complete(_ index: Int, with page: ScannedPage) {
        let continuation = requests[index].continuation
        requests[index].continuation = nil
        continuation?.resume(returning: page)
    }

    func fail(_ index: Int) {
        let continuation = requests[index].continuation
        requests[index].continuation = nil
        continuation?.resume(throwing: TestError.scannerFailure)
    }

    func sendProgress(_ value: Double, for index: Int) async {
        await requests[index].progress(value)
    }
}

private final class RecordingExporter: PDFExporting, @unchecked Sendable {
    struct Export {
        let pages: [ScannedPage]
        let url: URL
    }

    private let lock = NSLock()
    private var recorded: [Export] = []
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    var exports: [Export] { lock.withLock { recorded } }

    func export(pages: [ScannedPage], to url: URL) throws {
        try lock.withLock {
            recorded.append(Export(pages: pages, url: url))
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw TestError.exportFailure
            }
        }
    }
}

private enum TestError: Error {
    case timeout
    case scannerFailure
    case exportFailure
}
