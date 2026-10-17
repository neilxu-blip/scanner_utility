import CoreGraphics
import Foundation
import ImageIO
import PDFKit
@testable import ScannerCore
import XCTest

@MainActor
final class ScanimageMultipageTests: XCTestCase {
    private let selected = SANEDevice(id: "genesys:libusb:000:001", name: "Canon LiDE 120")

    func testAddressChangesBetweenPagesStillProduceOneOrderedMultipagePDF() async throws {
        let first = try png(gray: 1)
        let second = try png(gray: 0)
        let runner = ScriptedScannerRunner(steps: [
            listing("002"), .scan(first), listing("003"), .scan(second)
        ])
        let session = DocumentSession(backend: backend(runner))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("combined.pdf")

        session.start()
        try await waitForReady(session)
        XCTAssertNil(session.errorMessage)
        session.scanNext()
        try await waitForReady(session)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.pages.map(\.imageData), [first, second])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        await session.export(to: destination)
        XCTAssertEqual(session.phase, .saved)
        let pdf = try XCTUnwrap(PDFDocument(url: destination))
        XCTAssertEqual(pdf.pageCount, 2)
        let requests = await runner.requests
        XCTAssertEqual(scanAddresses(requests), ["--device-name=genesys:libusb:000:002", "--device-name=genesys:libusb:000:003"])
        XCTAssertEqual(requests.count, 4)
    }

    func testDisconnectOnSecondPageKeepsFirstPageAndAllowsRetry() async throws {
        let first = try png(gray: 1)
        let second = try png(gray: 0)
        let runner = ScriptedScannerRunner(steps: [
            listing("001"), .scan(first), .listing(""), listing("002"), .scan(second)
        ])
        let session = DocumentSession(backend: backend(runner))
        session.start()
        try await waitForReady(session)
        session.scanNext()
        try await waitForReady(session)
        XCTAssertEqual(session.pages.map(\.imageData), [first])
        XCTAssertTrue(session.errorMessage?.contains("completed pages") == true)

        session.scanNext()
        try await waitForReady(session)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.pages.map(\.imageData), [first, second])
        let requests = await runner.requests
        XCTAssertEqual(scanAddresses(requests).count, 2)
    }

    func testAmbiguousReplacementDoesNotScanAnArbitraryMatchingDevice() async throws {
        let runner = ScriptedScannerRunner(steps: [.listing(
            "genesys:libusb:000:002\tCanon\tLiDE 120\ngenesys:libusb:000:003\tCanon\tLiDE 120\n"
        )])
        do {
            _ = try await backend(runner).scanPage(number: 2, progress: { _ in })
            XCTFail("Expected an ambiguous-scanner error")
        } catch ScanimageError.ambiguousDevice {
            let requests = await runner.requests
            XCTAssertTrue(scanAddresses(requests).isEmpty)
        }
    }

    func testDifferentBackendIsNotUsedEvenWhenTheModelNameMatches() async throws {
        let runner = ScriptedScannerRunner(steps: [.listing("pixma:other-device\tCanon\tLiDE 120\n")])
        do {
            _ = try await backend(runner).scanPage(number: 2, progress: { _ in })
            XCTFail("Expected the selected backend to be unavailable")
        } catch ScanimageError.deviceUnavailable {
            let requests = await runner.requests
            XCTAssertTrue(scanAddresses(requests).isEmpty)
        }
    }

    func testAddressChangeBetweenDiscoveryAndOpenIsRecoveredOnce() async throws {
        let image = try png(gray: 1)
        let runner = ScriptedScannerRunner(steps: [
            listing("001"), openFailure("001"), listing("002"), .scan(image)
        ])
        let page = try await backend(runner).scanPage(number: 2, progress: { _ in })
        XCTAssertEqual(page.imageData, image)
        let requests = await runner.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(scanAddresses(requests), ["--device-name=genesys:libusb:000:001", "--device-name=genesys:libusb:000:002"])
    }

    func testFailedAcquisitionIsNeverAutomaticallyScannedAgain() async throws {
        for failure in [
            openFailure("001", output: Data([137, 80, 78, 71])),
            openFailure("001", progress: ["Progress: 0.0%\r"]),
            openFailure("001", progress: ["Progress: (unknown)\r"]),
            ScriptedScannerRunner.Step(isListing: false, result: ScanimageResult(output: Data(), diagnostic: "sane_read: I/O error", exitCode: 9))
        ] {
            let runner = ScriptedScannerRunner(steps: [listing("001"), failure])
            do {
                _ = try await backend(runner).scanPage(number: 2, progress: { _ in })
                XCTFail("Expected the acquisition error to be reported")
            } catch ScanimageError.commandFailed {
                let requests = await runner.requests
                XCTAssertEqual(requests.count, 2)
            }
        }
    }

    func testUnchangedAddressDoesNotCauseRepeatedOpenAttempts() async throws {
        let runner = ScriptedScannerRunner(steps: [listing("001"), openFailure("001"), listing("001")])
        do {
            _ = try await backend(runner).scanPage(number: 2, progress: { _ in })
            XCTFail("Expected the original open failure")
        } catch ScanimageError.commandFailed {
            let requests = await runner.requests
            XCTAssertEqual(requests.count, 3)
            XCTAssertEqual(scanAddresses(requests).count, 1)
        }
    }

    private func backend(_ runner: ScriptedScannerRunner) -> ScanimageScannerBackend {
        ScanimageScannerBackend(client: ScanimageClient(executable: URL(fileURLWithPath: "/test/scanimage"), runner: runner), device: selected)
    }

    private func listing(_ address: String) -> ScriptedScannerRunner.Step {
        .listing("genesys:libusb:000:\(address)\tCanon\tLiDE 120\n")
    }

    private func openFailure(_ address: String, output: Data = Data(), progress: [String] = []) -> ScriptedScannerRunner.Step {
        .init(isListing: false, result: ScanimageResult(
            output: output, diagnostic: "scanimage: open of device genesys:libusb:000:\(address) failed: Invalid argument", exitCode: 4
        ), diagnostics: progress)
    }

    private func scanAddresses(_ requests: [[String]]) -> [String] {
        requests.compactMap { $0.first }.filter { $0.hasPrefix("--device-name=") }
    }

    private func waitForReady(_ session: DocumentSession) async throws {
        for _ in 0..<200 {
            if session.phase == .ready { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Document session did not finish acquiring the page")
        throw ScriptedScannerRunner.Failure.unexpectedRequest
    }

    private func png(gray: CGFloat) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private actor ScriptedScannerRunner: ScanimageRunning {
    enum Failure: Error { case unexpectedRequest }

    struct Step: Sendable {
        let isListing: Bool
        let result: ScanimageResult
        var diagnostics: [String] = []

        static func listing(_ output: String) -> Step {
            Step(isListing: true, result: ScanimageResult(output: Data(output.utf8)))
        }

        static func scan(_ image: Data) -> Step {
            Step(isListing: false, result: ScanimageResult(output: image))
        }
    }

    private var steps: [Step]
    private(set) var requests: [[String]] = []

    init(steps: [Step]) { self.steps = steps }

    func run(executable: URL, arguments: [String], timeout: TimeInterval,
             onDiagnostic: @escaping @Sendable (Data) -> Void) async throws -> ScanimageResult {
        requests.append(arguments)
        guard !steps.isEmpty else { throw Failure.unexpectedRequest }
        let step = steps.removeFirst()
        guard step.isListing == (arguments.first?.hasPrefix("--formatted-device-list=") == true) else {
            throw Failure.unexpectedRequest
        }
        for chunk in step.diagnostics { onDiagnostic(Data(chunk.utf8)) }
        return step.result
    }
}
