import Foundation
import ScannerCore

enum PDFPreferences {
    static let compressionKey = "pdfCompression"
}

/// Reads the preference once when saving; acquisition retains the original PNGs.
struct PreferredPDFExporter: PDFExporting {
    func export(pages: [ScannedPage], to url: URL) throws {
        let rawValue = UserDefaults.standard.string(forKey: PDFPreferences.compressionKey) ?? ""
        let compression = PDFCompression(rawValue: rawValue) ?? .standard
        try PDFExporter(compression: compression).export(pages: pages, to: url)
    }
}
