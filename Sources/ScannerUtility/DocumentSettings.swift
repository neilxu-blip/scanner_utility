import Combine
import Foundation
import ScannerCore

enum AfterSaveAction: String, CaseIterable, Codable, Sendable {
    case none, openPreview, revealInFinder, openApplication, copyToFolder, composeEmail, extractText

    var displayName: String {
        switch self {
        case .none: "Do not open an application"
        case .openPreview: "Open in Preview"
        case .revealInFinder: "Show in Finder"
        case .openApplication: "Open in another application"
        case .copyToFolder: "Also copy to another folder"
        case .composeEmail: "Create an email draft with attachments"
        case .extractText: "Recognize text and save a text file"
        }
    }
}

enum SendImageSize: String, CaseIterable, Codable, Sendable {
    case original, small, medium, large

    var maxPixelDimension: Int? {
        switch self {
        case .original: nil
        case .small: 640
        case .medium: 800
        case .large: 1024
        }
    }

    var displayName: String {
        switch self {
        case .original: "No change"
        case .small: "Small (up to 640 pixels)"
        case .medium: "Medium (up to 800 pixels)"
        case .large: "Large (up to 1024 pixels)"
        }
    }
}

struct GeneralSettings: Equatable, Codable, Sendable {
    var recognitionLanguage = "en-US"
    var sendImageSize = SendImageSize.original
    var temporaryDirectory = FileManager.default.temporaryDirectory

    func normalized() -> Self {
        var result = self
        if !["", "en-US", "zh-Hans", "zh-Hant", "ja-JP", "fr-FR", "de-DE", "es-ES"].contains(recognitionLanguage) {
            result.recognitionLanguage = "en-US"
        }
        if !DocumentSettings.isValidDirectoryURL(temporaryDirectory) {
            result.temporaryDirectory = FileManager.default.temporaryDirectory
        }
        return result
    }
}

/// Each on-screen scan mode owns an independent profile. Views edit drafts and
/// persist them only on OK; the document profile preserves prior preferences.
struct DocumentSettings: Equatable, Sendable, Codable {
    var scanOptions = DocumentScanOptions()
    var compression = PDFCompression.standard
    var filenamePrefix = "Scanned Document"
    var saveDirectory = DocumentSettings.defaultSaveDirectory
    var useDateSubfolder = false
    var afterSave = AfterSaveAction.none
    var source = ScanSource.document
    var outputFormat = ScanOutputFormat.pdf
    var jpegQuality = 0.9
    var searchablePDF = false
    var checkScanResults = true
    var processing = ImageProcessingOptions()
    var stitchDirection = StitchDirection.horizontal
    var stitchOverlap = 0.15
    var applicationURL: URL?
    var secondaryDirectory: URL?

    init() {}

    static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    }

    static func defaults(for mode: ScanWorkflowMode) -> Self {
        var result = Self()
        switch mode {
        case .document: break
        case .auto:
            result.source = .automatic
            result.outputFormat = .automatic
            result.filenamePrefix = "Auto Scan"
            result.processing.autoCrop = true
        case .photo:
            result.source = .photo
            result.outputFormat = .jpeg
            result.filenamePrefix = "Scanned Photo"
            result.scanOptions.paperSize = .photo4x6
            result.scanOptions.resolution = .dpi600
        case .custom:
            result.filenamePrefix = "Custom Scan"
        case .stitch:
            result.outputFormat = .png
            result.filenamePrefix = "Stitched Scan"
        case .advanced:
            result.outputFormat = .png
            result.filenamePrefix = "Advanced Scan"
        }
        return result
    }

    /// Legacy fields remain independently validated, and loading never changes
    /// stored preferences. New profiles take precedence once explicitly saved.
    static func load(from defaults: UserDefaults = .standard) -> Self {
        if let data = defaults.data(forKey: DocumentSettingsKeys.profile(.document)),
           let profile = try? JSONDecoder().decode(Self.self, from: data) {
            return profile.normalized()
        }
        var settings = Self()
        if let value = defaults.object(forKey: DocumentSettingsKeys.colorMode) as? String,
           let mode = ScanColorMode(rawValue: value) {
            settings.scanOptions.colorMode = mode
        }
        if let value = defaults.object(forKey: DocumentSettingsKeys.paperSize) as? String,
           let size = ScanPaperSize(rawValue: value) {
            settings.scanOptions.paperSize = size
        }
        // Version 0.6 wrote only these three values. Preserve its validation
        // behavior while expanded resolutions are stored in versioned profiles.
        if let value = defaults.object(forKey: DocumentSettingsKeys.resolution) as? Int,
           [150, 300, 600].contains(value), let resolution = ScanResolution(rawValue: value) {
            settings.scanOptions.resolution = resolution
        }
        if let value = defaults.object(forKey: PDFPreferences.compressionKey) as? String,
           let compression = PDFCompression(rawValue: value) {
            settings.compression = compression
        }
        if let value = defaults.object(forKey: DocumentSettingsKeys.filenamePrefix) as? String {
            settings.filenamePrefix = ScanFilename.sanitizedPrefix(value)
        }
        if let value = defaults.object(forKey: DocumentSettingsKeys.saveDirectory) as? String,
           let url = URL(string: value), isValidDirectoryURL(url) {
            settings.saveDirectory = url
        }
        if let value = defaults.object(forKey: DocumentSettingsKeys.useDateSubfolder) as? Bool {
            settings.useDateSubfolder = value
        }
        if let value = defaults.object(forKey: DocumentSettingsKeys.afterSave) as? String,
           let action = AfterSaveAction(rawValue: value) {
            settings.afterSave = action
        }
        return settings
    }

    static func isValidDirectoryURL(_ url: URL) -> Bool {
        // Remember unavailable external volumes; the save dialog can choose a
        // replacement without discarding the user's saved preference.
        url.isFileURL && url.path.hasPrefix("/") && !url.path.contains("\0")
    }

    func normalized() -> Self {
        var result = self
        result.filenamePrefix = ScanFilename.sanitizedPrefix(filenamePrefix)
        if !Self.isValidDirectoryURL(saveDirectory) { result.saveDirectory = Self.defaultSaveDirectory }
        if let secondaryDirectory, !Self.isValidDirectoryURL(secondaryDirectory) { result.secondaryDirectory = nil }
        if let applicationURL, !Self.isValidDirectoryURL(applicationURL) || applicationURL.pathExtension.lowercased() != "app" {
            result.applicationURL = nil
        }
        result.jpegQuality = clamped(jpegQuality, to: 0.1...1, fallback: 0.9)
        result.stitchOverlap = clamped(stitchOverlap, to: 0...0.5, fallback: 0.15)
        result.scanOptions.customWidthMillimeters = clamped(scanOptions.customWidthMillimeters, to: 10...216, fallback: 210)
        result.scanOptions.customHeightMillimeters = clamped(scanOptions.customHeightMillimeters, to: 10...297, fallback: 297)
        result.processing.brightness = clamped(processing.brightness, to: -1...1, fallback: 0)
        result.processing.contrast = clamped(processing.contrast, to: -1...1, fallback: 0)
        result.processing.gamma = clamped(processing.gamma, to: 0.1...3, fallback: 1)
        return result
    }

    private func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }

    private enum CodingKeys: String, CodingKey {
        case scanOptions, compression, filenamePrefix, saveDirectory, useDateSubfolder, afterSave
        case source, outputFormat, jpegQuality, searchablePDF, checkScanResults, processing
        case stitchDirection, stitchOverlap, applicationURL, secondaryDirectory
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? values.decode(DocumentScanOptions.self, forKey: .scanOptions) { scanOptions = value }
        if let value = try? values.decode(String.self, forKey: .compression), let known = PDFCompression(rawValue: value) { compression = known }
        if let value = try? values.decode(String.self, forKey: .filenamePrefix) { filenamePrefix = value }
        if let value = try? values.decode(URL.self, forKey: .saveDirectory) { saveDirectory = value }
        if let value = try? values.decode(Bool.self, forKey: .useDateSubfolder) { useDateSubfolder = value }
        if let value = try? values.decode(AfterSaveAction.self, forKey: .afterSave) { afterSave = value }
        if let value = try? values.decode(ScanSource.self, forKey: .source) { source = value }
        if let value = try? values.decode(ScanOutputFormat.self, forKey: .outputFormat) { outputFormat = value }
        if let value = try? values.decode(Double.self, forKey: .jpegQuality) { jpegQuality = value }
        if let value = try? values.decode(Bool.self, forKey: .searchablePDF) { searchablePDF = value }
        if let value = try? values.decode(Bool.self, forKey: .checkScanResults) { checkScanResults = value }
        if let value = try? values.decode(ImageProcessingOptions.self, forKey: .processing) { processing = value }
        if let value = try? values.decode(StitchDirection.self, forKey: .stitchDirection) { stitchDirection = value }
        if let value = try? values.decode(Double.self, forKey: .stitchOverlap) { stitchOverlap = value }
        applicationURL = try? values.decode(URL.self, forKey: .applicationURL)
        secondaryDirectory = try? values.decode(URL.self, forKey: .secondaryDirectory)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(scanOptions, forKey: .scanOptions)
        try values.encode(compression.rawValue, forKey: .compression)
        try values.encode(filenamePrefix, forKey: .filenamePrefix)
        try values.encode(saveDirectory, forKey: .saveDirectory)
        try values.encode(useDateSubfolder, forKey: .useDateSubfolder)
        try values.encode(afterSave, forKey: .afterSave)
        try values.encode(source, forKey: .source)
        try values.encode(outputFormat, forKey: .outputFormat)
        try values.encode(jpegQuality, forKey: .jpegQuality)
        try values.encode(searchablePDF, forKey: .searchablePDF)
        try values.encode(checkScanResults, forKey: .checkScanResults)
        try values.encode(processing, forKey: .processing)
        try values.encode(stitchDirection, forKey: .stitchDirection)
        try values.encode(stitchOverlap, forKey: .stitchOverlap)
        try values.encodeIfPresent(applicationURL, forKey: .applicationURL)
        try values.encodeIfPresent(secondaryDirectory, forKey: .secondaryDirectory)
    }
}

enum DocumentSettingsKeys {
    static let colorMode = "documentColorMode"
    static let paperSize = "documentPaperSize"
    static let resolution = "documentResolution"
    static let filenamePrefix = "documentFilenamePrefix"
    static let saveDirectory = "documentSaveDirectory"
    static let useDateSubfolder = "documentUseDateSubfolder"
    static let afterSave = "documentAfterSave"
    static let general = "generalScanSettings.v1"
    static func profile(_ mode: ScanWorkflowMode) -> String { "scanProfile.v1.\(mode.rawValue)" }
}

@MainActor
final class DocumentSettingsStore: ObservableObject {
    @Published private(set) var settings: DocumentSettings
    @Published private(set) var general: GeneralSettings
    @Published private var profiles: [ScanWorkflowMode: DocumentSettings]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let document = DocumentSettings.load(from: defaults)
        settings = document
        var loaded: [ScanWorkflowMode: DocumentSettings] = [.document: document]
        for mode in ScanWorkflowMode.allCases where mode != .document {
            if let data = defaults.data(forKey: DocumentSettingsKeys.profile(mode)),
               let profile = try? JSONDecoder().decode(DocumentSettings.self, from: data) {
                loaded[mode] = profile.normalized()
            } else {
                loaded[mode] = DocumentSettings.defaults(for: mode)
            }
        }
        profiles = loaded
        if let data = defaults.data(forKey: DocumentSettingsKeys.general),
           let saved = try? JSONDecoder().decode(GeneralSettings.self, from: data) {
            general = saved.normalized()
        } else { general = GeneralSettings() }
    }

    func settings(for mode: ScanWorkflowMode) -> DocumentSettings {
        profiles[mode] ?? Self.defaultSettings(for: mode)
    }

    static func defaultSettings(for mode: ScanWorkflowMode) -> DocumentSettings { DocumentSettings.defaults(for: mode) }
    func defaultSettings(for mode: ScanWorkflowMode) -> DocumentSettings { Self.defaultSettings(for: mode) }

    func save(_ draft: DocumentSettings) { save(draft, for: .document) }

    func save(_ draft: DocumentSettings, for mode: ScanWorkflowMode) {
        let normalized = draft.normalized()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: DocumentSettingsKeys.profile(mode))
        profiles[mode] = normalized
        if mode == .document {
            // Preserve the previous keys for compatibility with older builds.
            defaults.set(normalized.scanOptions.colorMode.rawValue, forKey: DocumentSettingsKeys.colorMode)
            defaults.set(normalized.scanOptions.paperSize.rawValue, forKey: DocumentSettingsKeys.paperSize)
            defaults.set(normalized.scanOptions.resolution.rawValue, forKey: DocumentSettingsKeys.resolution)
            defaults.set(normalized.compression.rawValue, forKey: PDFPreferences.compressionKey)
            defaults.set(normalized.filenamePrefix, forKey: DocumentSettingsKeys.filenamePrefix)
            defaults.set(normalized.saveDirectory.absoluteString, forKey: DocumentSettingsKeys.saveDirectory)
            defaults.set(normalized.useDateSubfolder, forKey: DocumentSettingsKeys.useDateSubfolder)
            defaults.set(normalized.afterSave.rawValue, forKey: DocumentSettingsKeys.afterSave)
            settings = normalized
        }
    }

    func saveGeneral(_ draft: GeneralSettings) {
        let normalized = draft.normalized()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: DocumentSettingsKeys.general)
        general = normalized
    }

    func resetToDefaults() { save(DocumentSettings()) }
}
