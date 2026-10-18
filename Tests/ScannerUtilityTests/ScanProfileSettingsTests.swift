import Foundation
import ScannerCore
@testable import ScannerUtility
import XCTest

@MainActor
final class ScanProfileSettingsTests: XCTestCase {
    func testModeDefaultsAreIndependentAndDocumentDefaultsRemainUnchanged() throws {
        let defaults = try isolatedDefaults()
        let store = DocumentSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, DocumentSettings())
        XCTAssertEqual(store.settings(for: .document).scanOptions, DocumentScanOptions())
        XCTAssertEqual(store.settings(for: .photo).scanOptions.resolution, .dpi600)
        XCTAssertEqual(store.settings(for: .photo).scanOptions.paperSize, .photo4x6)
        XCTAssertEqual(store.settings(for: .photo).source, .photo)
        XCTAssertEqual(store.settings(for: .photo).outputFormat, .jpeg)
        XCTAssertEqual(store.settings(for: .auto).source, .automatic)
        XCTAssertEqual(store.settings(for: .auto).outputFormat, .automatic)
        XCTAssertEqual(store.settings(for: .stitch).outputFormat, .png)
        XCTAssertEqual(store.settings(for: .advanced).outputFormat, .png)
        XCTAssertEqual(store.settings(for: .custom).outputFormat, .pdf)
        for mode in ScanWorkflowMode.allCases {
            XCTAssertNil(defaults.object(forKey: DocumentSettingsKeys.profile(mode)))
        }
    }

    func testSavingPhotoProfileDoesNotChangeDocumentOrOtherModes() throws {
        let defaults = try isolatedDefaults()
        let store = DocumentSettingsStore(defaults: defaults)
        var photo = store.settings(for: .photo)
        photo.filenamePrefix = "Family Photos"
        photo.scanOptions.resolution = .dpi1200
        photo.outputFormat = .tiff
        photo.jpegQuality = 0.8
        photo.processing.autoEnhance = true
        store.save(photo, for: .photo)

        let reopened = DocumentSettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.settings(for: .photo), photo)
        XCTAssertEqual(reopened.settings, DocumentSettings())
        XCTAssertEqual(reopened.settings(for: .custom), DocumentSettings.defaults(for: .custom))
        XCTAssertNil(defaults.object(forKey: DocumentSettingsKeys.colorMode))
        XCTAssertNil(defaults.object(forKey: PDFPreferences.compressionKey))
    }

    func testExpandedDocumentProfileRoundTripsAllOptionsAndMaintainsLegacyKeys() throws {
        let defaults = try isolatedDefaults()
        let store = DocumentSettingsStore(defaults: defaults)
        var profile = store.settings
        profile.scanOptions.colorMode = .blackAndWhite
        profile.scanOptions.paperSize = .custom
        profile.scanOptions.customWidthMillimeters = 180
        profile.scanOptions.customHeightMillimeters = 250
        profile.scanOptions.resolution = .dpi400
        profile.source = .magazine
        profile.outputFormat = .png
        profile.compression = .highQuality
        profile.jpegQuality = 0.7
        profile.searchablePDF = true
        profile.checkScanResults = false
        profile.processing.autoCrop = true
        profile.processing.reduceMoire = true
        profile.processing.autoRotate = true
        profile.processing.brightness = 0.2
        profile.processing.contrast = -0.1
        profile.processing.gamma = 1.4
        profile.stitchDirection = .vertical
        profile.stitchOverlap = 0.2
        profile.afterSave = .openApplication
        profile.applicationURL = URL(fileURLWithPath: "/Applications/Preview.app", isDirectory: true)
        profile.secondaryDirectory = URL(fileURLWithPath: "/Volumes/Scans", isDirectory: true)
        store.save(profile)

        XCTAssertEqual(DocumentSettings.load(from: defaults), profile)
        XCTAssertEqual(DocumentSettingsStore(defaults: defaults).settings, profile)
        XCTAssertEqual(defaults.integer(forKey: DocumentSettingsKeys.resolution), 400)
        XCTAssertEqual(defaults.string(forKey: PDFPreferences.compressionKey), "highQuality")
    }

    func testLegacyMigrationReadsWithoutWritingAndResetOnlyTouchesDocument() throws {
        let defaults = try isolatedDefaults()
        defaults.set("grayscale", forKey: DocumentSettingsKeys.colorMode)
        defaults.set("letter", forKey: DocumentSettingsKeys.paperSize)
        defaults.set(600, forKey: DocumentSettingsKeys.resolution)
        defaults.set("highQuality", forKey: PDFPreferences.compressionKey)
        defaults.set("Invoices", forKey: DocumentSettingsKeys.filenamePrefix)
        let store = DocumentSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.scanOptions.colorMode, .grayscale)
        XCTAssertEqual(store.settings.scanOptions.paperSize, .letter)
        XCTAssertEqual(store.settings.scanOptions.resolution, .dpi600)
        XCTAssertEqual(store.settings.filenamePrefix, "Invoices")
        XCTAssertNil(defaults.data(forKey: DocumentSettingsKeys.profile(.document)))

        var photo = store.settings(for: .photo)
        photo.filenamePrefix = "Keep My Photos"
        store.save(photo, for: .photo)
        var general = store.general
        general.recognitionLanguage = "ja-JP"
        store.saveGeneral(general)
        store.resetToDefaults()
        XCTAssertEqual(store.settings, DocumentSettings())
        XCTAssertEqual(store.settings(for: .photo), photo)
        XCTAssertEqual(store.general, general)
    }

    func testInvalidProfileFieldsAreNormalizedBeforePersisting() throws {
        let store = DocumentSettingsStore(defaults: try isolatedDefaults())
        var profile = store.settings(for: .advanced)
        profile.filenamePrefix = "../Unsafe: Name\n"
        profile.jpegQuality = .nan
        profile.stitchOverlap = 2
        profile.scanOptions.customWidthMillimeters = .infinity
        profile.scanOptions.customHeightMillimeters = 900
        profile.processing.brightness = -2
        profile.processing.contrast = 4
        profile.processing.gamma = 0
        profile.saveDirectory = try XCTUnwrap(URL(string: "https://example.invalid/scans"))
        profile.applicationURL = URL(fileURLWithPath: "/tmp/not-an-application.txt")
        profile.secondaryDirectory = try XCTUnwrap(URL(string: "https://example.invalid/copy"))
        store.save(profile, for: .advanced)
        let normalized = store.settings(for: .advanced)
        XCTAssertEqual(normalized.filenamePrefix, "Unsafe Name")
        XCTAssertEqual(normalized.jpegQuality, 0.9)
        XCTAssertEqual(normalized.stitchOverlap, 0.5)
        XCTAssertEqual(normalized.scanOptions.customWidthMillimeters, 210)
        XCTAssertEqual(normalized.scanOptions.customHeightMillimeters, 297)
        XCTAssertEqual(normalized.processing.brightness, -1)
        XCTAssertEqual(normalized.processing.contrast, 1)
        XCTAssertEqual(normalized.processing.gamma, 0.1)
        XCTAssertEqual(normalized.saveDirectory, DocumentSettings.defaultSaveDirectory)
        XCTAssertNil(normalized.applicationURL)
        XCTAssertNil(normalized.secondaryDirectory)
    }

    func testUnknownFieldsDoNotDiscardOtherValidProfilePreferences() throws {
        let defaults = try isolatedDefaults()
        let payload: [String: Any] = [
            "compression": "future-compression", "outputFormat": "future-format",
            "afterSave": "future-action", "filenamePrefix": "Retained", "jpegQuality": 0.5,
            "saveDirectory": "https://example.invalid/scans", "checkScanResults": false,
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: DocumentSettingsKeys.profile(.document))
        let loaded = DocumentSettings.load(from: defaults)
        XCTAssertEqual(loaded.filenamePrefix, "Retained")
        XCTAssertEqual(loaded.compression, .standard)
        XCTAssertEqual(loaded.outputFormat, .pdf)
        XCTAssertEqual(loaded.afterSave, .none)
        XCTAssertEqual(loaded.jpegQuality, 0.5)
        XCTAssertFalse(loaded.checkScanResults)
        XCTAssertEqual(loaded.saveDirectory, DocumentSettings.defaultSaveDirectory)
    }

    func testGeneralPreferencesRoundTripAndDoNotChangeProfiles() throws {
        let defaults = try isolatedDefaults()
        let store = DocumentSettingsStore(defaults: defaults)
        var general = store.general
        general.recognitionLanguage = "zh-Hans"
        general.sendImageSize = .medium
        general.temporaryDirectory = URL(fileURLWithPath: "/Volumes/Outgoing", isDirectory: true)
        store.saveGeneral(general)
        let reopened = DocumentSettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.general, general)
        XCTAssertEqual(reopened.settings, DocumentSettings())
        XCTAssertEqual(reopened.settings(for: .photo), DocumentSettings.defaults(for: .photo))
        XCTAssertNil(defaults.data(forKey: DocumentSettingsKeys.profile(.document)))
    }

    func testGeneralInvalidValuesAndCanonSendImageLimits() throws {
        let store = DocumentSettingsStore(defaults: try isolatedDefaults())
        var general = GeneralSettings()
        general.recognitionLanguage = "unsupported-language"
        general.temporaryDirectory = try XCTUnwrap(URL(string: "https://example.invalid/tmp"))
        store.saveGeneral(general)
        XCTAssertEqual(store.general.recognitionLanguage, "en-US")
        XCTAssertEqual(store.general.temporaryDirectory, FileManager.default.temporaryDirectory)
        general.recognitionLanguage = ""
        store.saveGeneral(general)
        XCTAssertEqual(store.general.recognitionLanguage, "")
        XCTAssertNil(SendImageSize.original.maxPixelDimension)
        XCTAssertEqual(SendImageSize.small.maxPixelDimension, 640)
        XCTAssertEqual(SendImageSize.medium.maxPixelDimension, 800)
        XCTAssertEqual(SendImageSize.large.maxPixelDimension, 1024)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "ScannerUtilityTests.ScanProfiles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
