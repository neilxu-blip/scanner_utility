import Foundation
import ScannerCore

enum PDFPreferences {
    static let compressionKey = "pdfCompression"
}

/// Reads the preference once when saving; acquisition retains the original PNGs.
struct PreferredPDFExporter: PDFExporting {
    var paperSize: ScanPaperSize = .a4

    func export(pages: [ScannedPage], to url: URL) throws {
        let compression = DocumentSettings.load().compression
        try PDFExporter(compression: compression, paperSize: paperSize).export(pages: pages, to: url)
    }
}
