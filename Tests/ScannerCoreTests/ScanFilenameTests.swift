import Foundation
import ScannerCore
import XCTest

final class ScanFilenameTests: XCTestCase {
    func testSuggestedNameIncludesFilenameSafeDateAndTimeToTheSecond() throws {
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ScanFilename.suggested(date: date, timeZone: utc), "Scanned Document 1970-01-01_00-00-00.pdf")
        XCTAssertEqual(ScanFilename.suggested(date: date.addingTimeInterval(1), timeZone: utc),
                       "Scanned Document 1970-01-01_00-00-01.pdf")
    }

    func testSuggestedNameUsesTheSelectedLocalTimeZoneAcrossDateBoundaries() throws {
        let central = try XCTUnwrap(TimeZone(secondsFromGMT: -6 * 3_600))
        XCTAssertEqual(ScanFilename.suggested(date: Date(timeIntervalSince1970: 0), timeZone: central),
                       "Scanned Document 1969-12-31_18-00-00.pdf")
    }
}
