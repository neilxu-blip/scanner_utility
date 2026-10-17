import Foundation
import ScannerCore
@testable import ScannerUtility
import XCTest

@MainActor
final class ScannerDiscoveryTests: XCTestCase {
    private let canonID = "genesys:usb:1"
    private let canonListing = "genesys:usb:1\tCanon\tLiDE 120\n"

    func testNoScannerInNormalModeHasNoBackendOrMockFallback() async {
        let discovery = makeDiscovery(listings: [""])
        XCTAssertFalse(discovery.debugModeEnabled)
        XCTAssertFalse(discovery.hasAvailableScanner)
        await discovery.refresh()
        XCTAssertNil(discovery.selectedScannerID)
        XCTAssertNil(discovery.selectedBackend)
        XCTAssertEqual(discovery.selectedScannerName, "No scanner connected")
    }

    func testMissingSANEOnlyOffersMockAfterEnablingDebug() async {
        let discovery = ScannerDiscovery(clientProvider: { nil })
        await discovery.refresh()
        XCTAssertNil(discovery.selectedBackend)
        XCTAssertFalse(discovery.message?.contains("Mock Scanner") ?? true)
        discovery.setDebugModeEnabled(true)
        XCTAssertTrue(discovery.isMockSelected)
        XCTAssertEqual(discovery.selectedBackend?.displayName, "Mock Scanner")
        discovery.setDebugModeEnabled(false)
        XCTAssertNil(discovery.selectedScannerID)
        XCTAssertNil(discovery.selectedBackend)
    }

    func testLaunchDiscoverySelectsRealScannerInBothModes() async {
        for debug in [false, true] {
            let discovery = makeDiscovery(listings: [canonListing])
            discovery.setDebugModeEnabled(debug)
            await discovery.refresh()
            XCTAssertEqual(discovery.selectedScannerID, canonID)
            XCTAssertEqual(discovery.selectedBackend?.displayName, "Canon LiDE 120")
            XCTAssertFalse(discovery.isMockSelected)
        }
    }

    func testRefreshSelectsNewlyConnectedScannerInBothModes() async {
        for debug in [false, true] {
            let discovery = makeDiscovery(listings: ["", canonListing])
            discovery.setDebugModeEnabled(debug)
            await discovery.refresh()
            XCTAssertEqual(discovery.isMockSelected, debug)
            await discovery.refresh()
            XCTAssertEqual(discovery.selectedScannerID, canonID)
            XCTAssertEqual(discovery.selectedBackend?.displayName, "Canon LiDE 120")
        }
    }

    func testMockCanBeChosenExplicitlyButRefreshAndModeChangesPreferReal() async {
        let discovery = makeDiscovery(listings: [canonListing, canonListing])
        await discovery.refresh()
        discovery.setDebugModeEnabled(true)
        XCTAssertEqual(discovery.selectedScannerID, canonID)
        discovery.selectedScannerID = "mock"
        XCTAssertEqual(discovery.selectedBackend?.displayName, "Mock Scanner")
        await discovery.refresh()
        XCTAssertEqual(discovery.selectedScannerID, canonID)
        discovery.selectedScannerID = "mock"
        discovery.setDebugModeEnabled(false)
        XCTAssertEqual(discovery.selectedScannerID, canonID)
        // A stale mock selection must never provide a backend outside Debug Mode.
        discovery.selectedScannerID = "mock"
        XCTAssertNil(discovery.selectedBackend)
        XCTAssertFalse(discovery.hasAvailableScanner)
    }

    func testRefreshPreservesChosenRealScannerAndFallsBackWhenItDisconnects() async {
        let other = "other:usb:2\tOther\tScanner\n"
        let discovery = makeDiscovery(listings: [canonListing + other, canonListing + other, canonListing])
        await discovery.refresh()
        discovery.selectedScannerID = "other:usb:2"
        await discovery.refresh()
        XCTAssertEqual(discovery.selectedScannerName, "Other Scanner")
        await discovery.refresh()
        XCTAssertEqual(discovery.selectedScannerID, canonID)
    }

    func testDisconnectedScannerClearsSelectionUnlessDebugAllowsMock() async {
        for debug in [false, true] {
            let discovery = makeDiscovery(listings: [canonListing, ""])
            discovery.setDebugModeEnabled(debug)
            await discovery.refresh()
            await discovery.refresh()
            XCTAssertEqual(discovery.hasAvailableScanner, debug)
            XCTAssertEqual(discovery.isMockSelected, debug)
            XCTAssertEqual(discovery.selectedScannerID, debug ? "mock" : nil)
        }
    }

    func testFailedDiscoveryClearsStaleRealSelectionWithoutEnablingMock() async {
        let runner = ListingRunner(results: [
            ScanimageResult(output: Data(canonListing.utf8)),
            ScanimageResult(output: Data(), diagnostic: "USB unavailable", exitCode: 1)
        ])
        let discovery = makeDiscovery(runner: runner)
        await discovery.refresh()
        XCTAssertEqual(discovery.selectedScannerID, canonID)
        await discovery.refresh()
        XCTAssertNil(discovery.selectedScannerID)
        XCTAssertNil(discovery.selectedBackend)
        XCTAssertTrue(discovery.message?.contains("USB unavailable") ?? false)
    }

    private func makeDiscovery(listings: [String]) -> ScannerDiscovery {
        makeDiscovery(runner: ListingRunner(results: listings.map {
            ScanimageResult(output: Data($0.utf8))
        }))
    }

    private func makeDiscovery(runner: ListingRunner) -> ScannerDiscovery {
        ScannerDiscovery(clientProvider: {
            ScanimageClient(executable: URL(fileURLWithPath: "/test/scanimage"), runner: runner)
        })
    }
}

private actor ListingRunner: ScanimageRunning {
    private var results: [ScanimageResult]

    init(results: [ScanimageResult]) { self.results = results }

    func run(executable: URL, arguments: [String], timeout: TimeInterval,
             onDiagnostic: @escaping @Sendable (Data) -> Void) async throws -> ScanimageResult {
        // These tests exercise discovery only. Never substitute an acquisition command.
        guard arguments == ["--formatted-device-list=%d\t%v\t%m%n"], !results.isEmpty else {
            throw ListingError.unexpectedCommand
        }
        return results.removeFirst()
    }
}

private enum ListingError: Error {
    case unexpectedCommand
}
