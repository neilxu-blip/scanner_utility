import CoreGraphics
import Foundation
import ImageIO
import ScannerCore

/// A complete immutable save configuration, captured when the save dialog opens.
struct ScanOutputExporter: PDFExporting {
    let mode: ScanWorkflowMode
    let profile: DocumentSettings
    let general: GeneralSettings
    let format: ScanOutputFormat

    func export(pages: [ScannedPage], to url: URL) throws {
        var outputPages = pages
        var pageSize = profile.scanOptions.pdfSize
        if mode == .stitch {
            guard pages.count == 2 else { throw ScanWorkflowError.twoHalvesRequired }
            let joined = try ImageStitcher.stitch(pages[0], pages[1], direction: profile.stitchDirection, overlap: profile.stitchOverlap)
            if let source = CGImageSourceCreateWithData(pages[0].imageData as CFData, nil),
               let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
               let joinedSource = CGImageSourceCreateWithData(joined.imageData as CFData, nil),
               let joinedImage = CGImageSourceCreateImageAtIndex(joinedSource, 0, nil) {
                pageSize.width *= Double(joinedImage.width) / Double(original.width)
                pageSize.height *= Double(joinedImage.height) / Double(original.height)
            }
            outputPages = [joined]
        }
        if format == .pdf {
            try PDFExporter(
                compression: profile.compression, paperSize: profile.scanOptions.paperSize,
                searchable: profile.searchablePDF,
                recognitionLanguages: general.recognitionLanguage.isEmpty ? [] : [general.recognitionLanguage],
                pageSize: pageSize
            ).export(pages: outputPages, to: url)
        } else {
            try ImageExporter(format: format, jpegQuality: profile.jpegQuality).export(pages: outputPages, to: url)
        }
    }
}

enum ScanWorkflowError: LocalizedError {
    case twoHalvesRequired
    case actionDestinationMissing
    case actionUnavailable

    var errorDescription: String? {
        switch self {
        case .twoHalvesRequired: "Scan both overlapping halves before saving the stitched image."
        case .actionDestinationMissing: "Choose the application or additional destination folder in Settings."
        case .actionUnavailable: "The requested application action is not available on this Mac."
        }
    }
}
