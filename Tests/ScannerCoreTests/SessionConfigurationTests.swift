import Foundation
import ScannerCore
import XCTest

@MainActor
final class SessionConfigurationTests: XCTestCase {
    func testDocumentKeepsItsConfiguredScannerAndExporterUntilSaved() async throws {
        let original = ConfigurationScanner(name: "Original scanner")
        let replacement = ConfigurationScanner(name: "Replacement scanner")
        let initialExporter = ConfigurationExporter()
        let originalExporter = ConfigurationExporter()
        let replacementExporter = ConfigurationExporter()
        let session = DocumentSession(backend: replacement, exporter: initialExporter)

        // Starting a document installs its scanner and paper/export configuration together.
        XCTAssertTrue(session.selectBackend(original, exporter: originalExporter))
        session.start()
        XCTAssertFalse(session.selectBackend(replacement, exporter: replacementExporter))
        try await waitUntil { await original.requestCount == 1 }
        let first = ScannedPage(imageData: Data([1]))
        await original.complete(0, with: first)
        try await waitUntil { session.phase == .ready }
        XCTAssertFalse(session.selectBackend(replacement, exporter: replacementExporter))
        XCTAssertEqual(session.pages.map(\.id), [first.id])
        XCTAssertEqual(session.scannerDisplayName, "Original scanner")

        session.scanNext()
        XCTAssertFalse(session.selectBackend(replacement, exporter: replacementExporter))
        XCTAssertEqual(session.pages.map(\.id), [first.id])
        try await waitUntil { await original.requestCount == 2 }
        let second = ScannedPage(imageData: Data([2]))
        await original.complete(1, with: second)
        try await waitUntil { session.phase == .ready }
        XCTAssertFalse(session.selectBackend(replacement, exporter: replacementExporter))
        XCTAssertEqual(session.pages.map(\.id), [first.id, second.id])
        XCTAssertTrue(originalExporter.exports.isEmpty)

        let firstURL = URL(fileURLWithPath: "/unused/original-configuration.pdf")
        await session.export(to: firstURL)
        XCTAssertEqual(session.phase, .saved)
        XCTAssertEqual(originalExporter.exports.map(\.pageIDs), [[first.id, second.id]])
        XCTAssertEqual(originalExporter.exports.map(\.url), [firstURL])
        XCTAssertTrue(initialExporter.exports.isEmpty)
        XCTAssertTrue(replacementExporter.exports.isEmpty)
        let replacementRequestCount = await replacement.requestCount
        XCTAssertEqual(replacementRequestCount, 0)

        // Once saved, the next document may use a different scanner and paper configuration.
        XCTAssertTrue(session.selectBackend(replacement, exporter: replacementExporter))
        XCTAssertEqual(session.scannerDisplayName, "Replacement scanner")
        session.start()
        XCTAssertTrue(session.pages.isEmpty)
        try await waitUntil { await replacement.requestCount == 1 }
        let nextDocument = ScannedPage(imageData: Data([3]))
        await replacement.complete(0, with: nextDocument)
        try await waitUntil { session.phase == .ready }
        await session.export(to: URL(fileURLWithPath: "/unused/replacement-configuration.pdf"))
        XCTAssertEqual(session.phase, .saved)
        XCTAssertEqual(replacementExporter.exports.map(\.pageIDs), [[nextDocument.id]])
        XCTAssertEqual(originalExporter.exports.count, 1)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for configured document session")
        throw ConfigurationTestError.timeout
    }
}

private actor ConfigurationScanner: ScannerBackend {
    nonisolated let displayName: String
    private var requests: [CheckedContinuation<ScannedPage, any Error>?] = []
    var requestCount: Int { requests.count }

    init(name: String) { displayName = name }

    func scanPage(number: Int, progress: @escaping @Sendable (Double) async -> Void) async throws -> ScannedPage {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }

    func complete(_ index: Int, with page: ScannedPage) {
        let continuation = requests[index]
        requests[index] = nil
        continuation?.resume(returning: page)
    }
}

private final class ConfigurationExporter: PDFExporting, @unchecked Sendable {
    struct Export {
        let pageIDs: [UUID]
        let url: URL
    }

    private let lock = NSLock()
    private var recorded: [Export] = []
    var exports: [Export] { lock.withLock { recorded } }

    func export(pages: [ScannedPage], to url: URL) throws {
        lock.withLock { recorded.append(Export(pageIDs: pages.map(\.id), url: url)) }
    }
}

private enum ConfigurationTestError: Error {
    case timeout
}
