import Foundation
import ScannerCore
@testable import ScannerUtility
import XCTest

@MainActor
final class DocumentSettingsTests: XCTestCase {
    func testDefaultsMatchRequestedDocumentDefaultsWithoutWritingPreferences() throws {
        let defaults = try isolatedDefaults()
        let store = DocumentSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.scanOptions, DocumentScanOptions())
        XCTAssertEqual(store.settings.compression, .standard)
        XCTAssertEqual(store.settings.filenamePrefix, "Scanned Document")
        XCTAssertEqual(store.settings.saveDirectory, DocumentSettings.defaultSaveDirectory)
        XCTAssertFalse(store.settings.useDateSubfolder)
        XCTAssertEqual(store.settings.afterSave, .none)
        XCTAssertNil(defaults.object(forKey: DocumentSettingsKeys.colorMode))
        XCTAssertNil(defaults.object(forKey: PDFPreferences.compressionKey))
    }

    func testPreferencesRoundTripAndExistingCompressionKeyIsPreserved() throws {
        let defaults = try isolatedDefaults()
        // A preference written by the previous version must migrate unchanged.
        defaults.set(PDFCompression.highQuality.rawValue, forKey: PDFPreferences.compressionKey)
        let store = DocumentSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.compression, .highQuality)

        var draft = store.settings
        draft.scanOptions = DocumentScanOptions(colorMode: .grayscale, paperSize: .letter, resolution: .dpi600)
        draft.compression = .lossless
        draft.filenamePrefix = "Invoices"
        draft.saveDirectory = URL(fileURLWithPath: "/Volumes/Unavailable Scans", isDirectory: true)
        draft.useDateSubfolder = true
        draft.afterSave = .revealInFinder
        store.save(draft)

        XCTAssertEqual(store.settings, draft)
        XCTAssertEqual(DocumentSettings.load(from: defaults), draft)
        XCTAssertEqual(DocumentSettingsStore(defaults: defaults).settings, draft)
        XCTAssertEqual(defaults.string(forKey: PDFPreferences.compressionKey), "lossless")
    }

    func testInvalidFieldsFallBackIndependentlyWithoutDiscardingValidPreferences() throws {
        let defaults = try isolatedDefaults()
        defaults.set("future-color", forKey: DocumentSettingsKeys.colorMode)
        defaults.set("a5", forKey: DocumentSettingsKeys.paperSize)
        defaults.set(400, forKey: DocumentSettingsKeys.resolution)
        defaults.set("future-compression", forKey: PDFPreferences.compressionKey)
        defaults.set("https://example.invalid/scans", forKey: DocumentSettingsKeys.saveDirectory)
        defaults.set("future-action", forKey: DocumentSettingsKeys.afterSave)
        defaults.set(true, forKey: DocumentSettingsKeys.useDateSubfolder)
        defaults.set("  Bills/2026:\n", forKey: DocumentSettingsKeys.filenamePrefix)

        let loaded = DocumentSettings.load(from: defaults)
        XCTAssertEqual(loaded.scanOptions.colorMode, .color)
        XCTAssertEqual(loaded.scanOptions.paperSize, .a5)
        XCTAssertEqual(loaded.scanOptions.resolution, .dpi300)
        XCTAssertEqual(loaded.compression, .standard)
        XCTAssertEqual(loaded.saveDirectory, DocumentSettings.defaultSaveDirectory)
        XCTAssertEqual(loaded.afterSave, .none)
        XCTAssertEqual(loaded.filenamePrefix, "Bills 2026")
        XCTAssertTrue(loaded.useDateSubfolder)
        // Loading repairs the in-memory value without rewriting stored data.
        XCTAssertEqual(defaults.integer(forKey: DocumentSettingsKeys.resolution), 400)
    }

    func testUnsupportedOrWrongTypeResolutionAndDirectoryNeverReachScannerOrSavePanel() throws {
        let defaults = try isolatedDefaults()
        let invalidResolutions: [Any] = [0, 301, 600.5, "600", -300]
        for value in invalidResolutions {
            defaults.set(value, forKey: DocumentSettingsKeys.resolution)
            XCTAssertEqual(DocumentSettings.load(from: defaults).scanOptions.resolution, .dpi300)
        }
        for value in ["relative/scans", "file:relative", "", "file:///tmp/scans%00"] {
            defaults.set(value, forKey: DocumentSettingsKeys.saveDirectory)
            XCTAssertEqual(DocumentSettings.load(from: defaults).saveDirectory, DocumentSettings.defaultSaveDirectory)
        }
    }

    func testDraftIsNotPersistedUntilSaveAndSavedPrefixIsSafe() throws {
        let defaults = try isolatedDefaults()
        let store = DocumentSettingsStore(defaults: defaults)
        var draft = store.settings
        draft.filenamePrefix = "../Reports\\October:\n"
        draft.afterSave = .openPreview
        XCTAssertEqual(DocumentSettings.load(from: defaults), DocumentSettings())
        XCTAssertEqual(store.settings, DocumentSettings())

        store.save(draft)
        XCTAssertEqual(store.settings.filenamePrefix, "Reports October")
        XCTAssertEqual(store.settings.afterSave, .openPreview)
        XCTAssertEqual(DocumentSettings.load(from: defaults), store.settings)
    }

    func testSavingInvalidDestinationUsesDocumentsAndResetRestoresOnlyDocumentSettings() throws {
        let defaults = try isolatedDefaults()
        defaults.set("keep", forKey: "unrelatedPreference")
        let store = DocumentSettingsStore(defaults: defaults)
        var draft = store.settings
        draft.scanOptions = DocumentScanOptions(colorMode: .grayscale, paperSize: .b5, resolution: .dpi150)
        draft.filenamePrefix = "Work"
        draft.compression = .highQuality
        draft.useDateSubfolder = true
        draft.afterSave = .openPreview
        draft.saveDirectory = try XCTUnwrap(URL(string: "https://example.invalid"))
        store.save(draft)
        XCTAssertEqual(store.settings.saveDirectory, DocumentSettings.defaultSaveDirectory)

        store.resetToDefaults()
        XCTAssertEqual(store.settings, DocumentSettings())
        XCTAssertEqual(DocumentSettings.load(from: defaults), DocumentSettings())
        XCTAssertEqual(defaults.string(forKey: "unrelatedPreference"), "keep")
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "ScannerUtilityTests.DocumentSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
