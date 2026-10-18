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

    func testCustomPrefixIsAFilenameComponentAndKeepsTimestamp() throws {
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(ScanFilename.suggested(date: Date(timeIntervalSince1970: 0), timeZone: utc,
                                             prefix: " ../Invoices/October:\n\0 "),
                       "Invoices October 1970-01-01_00-00-00.pdf")
        XCTAssertEqual(ScanFilename.sanitizedPrefix("..\\..\\"), "Scanned Document")
        XCTAssertEqual(ScanFilename.sanitizedPrefix(" \n\t"), "Scanned Document")
        XCTAssertEqual(ScanFilename.sanitizedPrefix("  Tax   records  "), "Tax records")
    }

    func testLongUnicodePrefixIsBoundedWithoutBreakingCharacters() throws {
        let prefix = ScanFilename.sanitizedPrefix(String(repeating: "掃描🙂", count: 100))
        XCTAssertLessThanOrEqual(prefix.utf8.count, 180)
        XCTAssertFalse(prefix.isEmpty)
        XCTAssertFalse(prefix.contains("�"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertLessThan(ScanFilename.suggested(date: Date(timeIntervalSince1970: 0), timeZone: utc,
                                               prefix: prefix).utf8.count, 256)
    }

    func testDateSubfolderUsesLocalDateAndFilenameSafeSeparators() throws {
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let central = try XCTUnwrap(TimeZone(secondsFromGMT: -6 * 3_600))
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ScanFilename.dateSubfolder(date: date, timeZone: utc), "1970_01_01")
        XCTAssertEqual(ScanFilename.dateSubfolder(date: date, timeZone: central), "1969_12_31")
    }
}
