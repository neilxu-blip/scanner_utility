import Foundation
import ScannerCore
@testable import ScannerUtility
import XCTest

final class DocumentSavePlanTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_792_281_600)
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testPlanKeepsExplicitPanelFilenameAndDoesNotCreateFoldersUntilApprovedSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = DocumentSettings()
        settings.useDateSubfolder = true
        settings.afterSave = .revealInFinder
        let selected = root.appendingPathComponent("User chosen name.pdf")
        let plan = DocumentSavePlan(selectedURL: selected, settings: settings, date: date, timeZone: utc)
        XCTAssertEqual(plan.url.lastPathComponent, "User chosen name.pdf")
        XCTAssertEqual(plan.afterSave, .revealInFinder)
        XCTAssertEqual(plan.url.deletingLastPathComponent().lastPathComponent, ScanFilename.dateSubfolder(date: date, timeZone: utc))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.url.deletingLastPathComponent().path))
        try plan.prepareDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.url.deletingLastPathComponent().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.url.path))
    }

    func testNoSubfolderPreservesFullPanelChoiceAndExistingDatedFolderIsNotNested() throws {
        let base = URL(fileURLWithPath: "/chosen/folder")
        let selected = base.appendingPathComponent("Custom.pdf")
        var settings = DocumentSettings()
        XCTAssertEqual(DocumentSavePlan(selectedURL: selected, settings: settings).url, selected)
        settings.useDateSubfolder = true
        let dated = base.appendingPathComponent(ScanFilename.dateSubfolder(date: date, timeZone: utc), isDirectory: true)
            .appendingPathComponent("Custom.pdf")
        XCTAssertEqual(DocumentSavePlan(selectedURL: dated, settings: settings, date: date, timeZone: utc).url, dated)
    }

    func testDatedFolderCannotReplaceAUserFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = DocumentSettings()
        settings.useDateSubfolder = true
        let conflict = root.appendingPathComponent(ScanFilename.dateSubfolder(date: date, timeZone: utc))
        let original = Data("Keep this file".utf8)
        try original.write(to: conflict)
        let plan = DocumentSavePlan(selectedURL: root.appendingPathComponent("scan.pdf"), settings: settings, date: date, timeZone: utc)
        XCTAssertThrowsError(try plan.prepareDirectory())
        XCTAssertEqual(try Data(contentsOf: conflict), original)
    }
}
