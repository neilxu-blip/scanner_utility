import Foundation
@testable import ScannerCore
import XCTest

@MainActor
final class AdvancedScanOptionsTests: XCTestCase {
    func testOldPersistedOptionsDecodeWithCustomDefaults() throws {
        let old = Data(#"{"colorMode":"grayscale","paperSize":"letter","resolution":150}"#.utf8)
        let restored = try JSONDecoder().decode(DocumentScanOptions.self, from: old)
        XCTAssertEqual(restored, DocumentScanOptions(colorMode: .grayscale, paperSize: .letter, resolution: .dpi150))
        XCTAssertEqual(restored.customWidthMillimeters, 210)
        XCTAssertEqual(restored.customHeightMillimeters, 297)
    }

    func testCustomGeometryRoundTripsWithoutAffectingFixedPaper() throws {
        let options = DocumentScanOptions(
            colorMode: .blackAndWhite, paperSize: .custom, resolution: .dpi400,
            customWidthMillimeters: 120, customHeightMillimeters: 180
        )
        try options.validate()
        XCTAssertEqual(try JSONDecoder().decode(DocumentScanOptions.self, from: JSONEncoder().encode(options)), options)
        XCTAssertEqual(options.effectiveWidthMillimeters, 120)
        XCTAssertEqual(options.effectiveHeightMillimeters, 180)
        XCTAssertEqual(options.pdfSize.width, 120 * 72 / 25.4, accuracy: 0.000_001)
        var fixed = options
        fixed.paperSize = .photo4x6
        XCTAssertEqual(fixed.effectiveWidthMillimeters, 101.6)
        XCTAssertEqual(fixed.effectiveHeightMillimeters, 152.4)
    }

    func testValidationRejectsUnsafeGeometryAndExcessiveMemoryBeforeCallingSANE() async throws {
        let invalid = DocumentScanOptions(paperSize: .custom, customWidthMillimeters: .nan)
        for options in [invalid,
                        .init(paperSize: .custom, customWidthMillimeters: 217),
                        .init(paperSize: .custom, customHeightMillimeters: 298),
                        .init(colorMode: .grayscale, paperSize: .custom, resolution: .dpi1200,
                              customWidthMillimeters: 200, customHeightMillimeters: 220),
                        .init(resolution: .dpi1200)] {
            let runner = RecordingOptionRunner()
            let backend = ScanimageScannerBackend(
                client: ScanimageClient(executable: URL(fileURLWithPath: "/unused/scanimage"), runner: runner),
                device: SANEDevice(id: "test:device", name: "Test Scanner"), options: options
            )
            do {
                _ = try await backend.scanPage(number: 1, progress: { _ in })
                XCTFail("Expected invalid options")
            } catch is ScanOptionsError {}
            let calls = await runner.calls
            XCTAssertEqual(calls.count, 0)
        }
        try DocumentScanOptions(resolution: .dpi600).validate()
        try DocumentScanOptions(paperSize: .photo4x6, resolution: .dpi1200).validate()
    }

    func testBlackAndWhiteCustomScanUsesSupportedGrayAndExactGeometry() async throws {
        let runner = RecordingOptionRunner()
        let backend = ScanimageScannerBackend(
            client: ScanimageClient(executable: URL(fileURLWithPath: "/unused/scanimage"), runner: runner),
            device: SANEDevice(id: "test:device", name: "Test Scanner"),
            options: .init(colorMode: .blackAndWhite, paperSize: .custom, resolution: .dpi200,
                           customWidthMillimeters: 100.5, customHeightMillimeters: 150)
        )
        do { _ = try await backend.scanPage(number: 1, progress: { _ in }) }
        catch ScanimageError.invalidImage { /* Only command arguments matter here. */ }
        let calls = await runner.calls
        let arguments = try XCTUnwrap(calls.last)
        XCTAssertTrue(arguments.contains("--mode=Gray"))
        XCTAssertTrue(arguments.contains("--resolution=200"))
        XCTAssertEqual(Array(arguments.suffix(4)), ["-x", "100.5", "-y", "150"])
        XCTAssertFalse(arguments.contains { $0.contains("brightness") || $0.contains("contrast") || $0.contains("gamma") })
    }
}

private actor RecordingOptionRunner: ScanimageRunning {
    private(set) var calls: [[String]] = []

    func run(executable: URL, arguments: [String], timeout: TimeInterval,
             onDiagnostic: @escaping @Sendable (Data) -> Void) async throws -> ScanimageResult {
        calls.append(arguments)
        if arguments.first?.hasPrefix("--formatted-device-list=") == true {
            return ScanimageResult(output: Data("test:device\tTest\tScanner\n".utf8))
        }
        return ScanimageResult(output: Data())
    }
}
