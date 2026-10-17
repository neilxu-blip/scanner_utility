import CoreGraphics
import Foundation
import ImageIO
@testable import ScannerCore
import XCTest

@MainActor
final class ScanimageTests: XCTestCase {
    private let executable = URL(fileURLWithPath: "/test/scanimage")
    private let device = SANEDevice(id: "genesys:libusb:000:001", name: "Canon LiDE 120")
    private let deviceListing = "genesys:libusb:000:001\tCanon\tLiDE 120\n"

    func testDeviceDiscoveryUsesListingOnlyAndDeduplicatesDevices() async throws {
        let text = "genesys:usb:1\tCanon\tLiDE 120\nother:usb:2\tOther\tModel\n" +
            "genesys:usb:1\tCanon\tLiDE 120\nnot a device line\n"
        let runner = StubRunner(result: ScanimageResult(output: Data(text.utf8)))
        let devices = try await ScanimageClient(executable: executable, runner: runner).devices()
        XCTAssertEqual(devices.map(\.name), ["Canon LiDE 120", "Other Model"])
        let arguments = await runner.arguments
        XCTAssertEqual(arguments, [["--formatted-device-list=%d\t%v\t%m%n"]])
    }

    func testEmptyDeviceListIsAllowedAndFailureIsReported() async throws {
        let empty = StubRunner(result: ScanimageResult(output: Data()))
        let devices = try await ScanimageClient(executable: executable, runner: empty).devices()
        XCTAssertTrue(devices.isEmpty)
        let failure = StubRunner(result: ScanimageResult(output: Data(), diagnostic: "USB access denied", exitCode: 1))
        do {
            _ = try await ScanimageClient(executable: executable, runner: failure).devices()
            XCTFail("Expected detection error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("USB access denied"))
        }
    }

    func testScanCapturesPNGAndReportsSplitProgressWithoutShellOrOutputFiles() async throws {
        let png = try makePNG()
        let runner = StubRunner(result: ScanimageResult(output: png), chunks: [
            "Pro", "gress: 12.", "5%\rProgress: (unknown)\rProgress: 55.0%\r"
        ], deviceListing: deviceListing)
        let backend = ScanimageScannerBackend(client: ScanimageClient(executable: executable, runner: runner), device: device)
        let progress = ProgressValues()
        let page = try await backend.scanPage(number: 1) { await progress.append($0) }
        XCTAssertEqual(page.imageData, png)
        XCTAssertEqual(backend.displayName, "Canon LiDE 120")
        let values = await progress.values
        XCTAssertEqual(values, [0, 0.125, 0.55, 1])
        let arguments = await runner.arguments
        XCTAssertEqual(arguments, [["--formatted-device-list=%d\t%v\t%m%n"],
                                   ["--device-name=genesys:libusb:000:001", "--format=png", "--progress",
                                    "--mode=Color", "--resolution=300", "--depth=8",
                                    "-l", "0", "-t", "0", "-x", "210", "-y", "297"]])
    }

    func testScanRejectsFailedCommandAndIncompleteImage() async throws {
        for result in [ScanimageResult(output: Data(), diagnostic: "device busy", exitCode: 9),
                       ScanimageResult(output: Data("incomplete image".utf8))] {
            let runner = StubRunner(result: result, deviceListing: deviceListing)
            let backend = ScanimageScannerBackend(client: ScanimageClient(executable: executable, runner: runner), device: device)
            do {
                _ = try await backend.scanPage(number: 1, progress: { _ in })
                XCTFail("Expected a scan error")
            } catch is ScanimageError {
                // An invalid or failed acquisition must never be accepted as a page.
            }
        }
    }

    func testStatusDistinguishesWarmupUnknownProgressAndMeasuredAcquisition() async throws {
        let runner = StubRunner(result: ScanimageResult(output: try makePNG()), chunks: [
            "Progress: (unk", "nown)\rProgress: 0.0%\rProgress: 25.0%\r"
        ], deviceListing: deviceListing)
        let backend = ScanimageScannerBackend(client: ScanimageClient(executable: executable, runner: runner), device: device)
        let statuses = StatusValues()
        _ = try await backend.scanPage(number: 1, status: { await statuses.append($0) })
        let values = await statuses.values
        XCTAssertEqual(values, [.warmingUp, .scanning(progress: nil), .scanning(progress: 0),
                                .scanning(progress: 0.25), .scanning(progress: 1)])
    }

    func testProgressParserHandlesCarriageReturnsAndClampsValues() {
        let parser = ScanimageProgressParser()
        XCTAssertEqual(parser.append(Data("warming up\rProgress: (unknown)\rPro".utf8)), [])
        let values = parser.append(Data("gress: 33.3%\rProgress: 120.0%\r".utf8))
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(try! XCTUnwrap(values.first), 0.333, accuracy: 0.000_001)
        XCTAssertEqual(values.last, 1)
        XCTAssertEqual(parser.append(Data("device busy\n".utf8)), [])
    }

    func testProcessDrainsBothPipesBeyondPipeCapacity() async throws {
        let script = "i=0; while [ $i -lt 3000 ]; do printf '12345678901234567890123456789012'; printf 'abcdefghijklmnopqrstuvwxzy123456' >&2; i=$((i + 1)); done"
        let result = try await ScanimageProcess().run(
            executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script],
            timeout: 10, onDiagnostic: { _ in }
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.count, 96_000)
        XCTAssertEqual(result.diagnostic.utf8.count, 16_384)
    }

    func testSmallProgressMessageIsDeliveredBeforeTheProcessCanFinish() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let acknowledgement = directory.appendingPathComponent("progress-received")
        // The child cannot finish until its small stderr update reaches the callback.
        // A reader that waits for 16 KB or EOF will time out instead.
        let script = #"printf 'Progress: 25.0%%\r' >&2; while [ ! -e "$1" ]; do /bin/sleep 0.01; done; printf done"#
        let result = try await ScanimageProcess().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, "progress-test", acknowledgement.path], timeout: 2,
            onDiagnostic: { _ in try? Data().write(to: acknowledgement) }
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "done")
    }

    func testProcessReportsExitStatusAndDiagnostics() async throws {
        let result = try await ScanimageProcess().run(
            executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'device busy' >&2; exit 7"],
            timeout: 5, onDiagnostic: { _ in }
        )
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.diagnostic, "device busy")
    }

    func testProcessTimeoutStopsTheChild() async throws {
        do {
            _ = try await ScanimageProcess().run(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"],
                timeout: 0.1, onDiagnostic: { _ in }
            )
            XCTFail("Expected timeout")
        } catch ScanimageError.timedOut {
            // The child was reaped and the operation completed without waiting 10 seconds.
        }
    }

    func testProcessCancellationStopsTheChild() async throws {
        let task = Task {
            try await ScanimageProcess().run(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"],
                timeout: 20, onDiagnostic: { _ in }
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }

    func testSessionCannotChangeScannerUntilItsPagesAreSaved() async throws {
        let mock = ImmediateScanner(displayName: "Mock Scanner")
        let session = DocumentSession(backend: mock, exporter: DiscardingExporter())
        let real = ImmediateScanner(displayName: "Real Scanner")
        XCTAssertTrue(session.selectBackend(real))
        session.start()
        XCTAssertFalse(session.selectBackend(mock))
        for _ in 0..<100 where session.phase == .scanning {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(session.phase, .ready)
        XCTAssertFalse(session.selectBackend(mock))
        XCTAssertEqual(session.scannerDisplayName, "Real Scanner")
        await session.export(to: URL(fileURLWithPath: "/unused/test.pdf"))
        XCTAssertTrue(session.selectBackend(mock))
        XCTAssertEqual(session.scannerDisplayName, "Mock Scanner")
    }

    private func makePNG() throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private actor StubRunner: ScanimageRunning {
    let result: ScanimageResult
    let chunks: [String]
    let deviceListing: String?
    private(set) var arguments: [[String]] = []

    init(result: ScanimageResult, chunks: [String] = [], deviceListing: String? = nil) {
        self.result = result
        self.chunks = chunks
        self.deviceListing = deviceListing
    }

    func run(executable: URL, arguments: [String], timeout: TimeInterval,
             onDiagnostic: @escaping @Sendable (Data) -> Void) async throws -> ScanimageResult {
        self.arguments.append(arguments)
        if arguments.first?.hasPrefix("--formatted-device-list=") == true, let deviceListing {
            return ScanimageResult(output: Data(deviceListing.utf8))
        }
        for chunk in chunks { onDiagnostic(Data(chunk.utf8)) }
        return result
    }
}

private actor ProgressValues {
    private(set) var values: [Double] = []
    func append(_ value: Double) { values.append(value) }
}

private actor StatusValues {
    private(set) var values: [ScannerStatus] = []
    func append(_ value: ScannerStatus) { values.append(value) }
}

private struct ImmediateScanner: ScannerBackend {
    let displayName: String
    func scanPage(number: Int, progress: @escaping @Sendable (Double) async -> Void) async throws -> ScannedPage {
        ScannedPage(imageData: Data([1]))
    }
}

private struct DiscardingExporter: PDFExporting {
    func export(pages: [ScannedPage], to url: URL) throws {}
}
