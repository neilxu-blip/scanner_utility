import CoreGraphics
import Foundation
import ImageIO

/// Saves one acquired image without changing its pixel dimensions. PDF batches
/// use PDFExporter; image formats require an explicit single-image workflow.
public struct ImageExporter: PDFExporting {
    private let format: ScanOutputFormat
    private let jpegQuality: Double

    public init(format: ScanOutputFormat, jpegQuality: Double = 0.9) {
        self.format = format
        self.jpegQuality = jpegQuality
    }

    public func export(pages: [ScannedPage], to url: URL) throws {
        guard pages.count == 1 else { throw ImageExportError.singlePageRequired }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw PDFExportError.fileAlreadyExists
        }
        let type: CFString
        switch format {
        case .jpeg: type = "public.jpeg" as CFString
        case .png: type = "public.png" as CFString
        case .tiff: type = "public.tiff" as CFString
        case .automatic, .pdf: throw ImageExportError.unsupportedFormat
        }
        guard jpegQuality.isFinite, (0...1).contains(jpegQuality) else {
            throw ImageExportError.invalidQuality
        }
        guard let source = CGImageSourceCreateWithData(pages[0].imageData as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PDFExportError.invalidPage(1)
        }
        let image = format == .jpeg ? try opaqueImage(original) : original
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            throw ImageExportError.creationFailed
        }
        // Retain useful acquisition resolution metadata when present. Scanner
        // PNGs have no orientation transform, and we encode the decoded pixels.
        let originalProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var properties: [CFString: Any] = [:]
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            properties[key] = originalProperties[key]
        }
        if format == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality }
        if format == .tiff {
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageExportError.creationFailed }
        // Exclusive creation protects existing files even if one appears while
        // ImageIO is encoding the new image.
        try (data as Data).write(to: url, options: .withoutOverwriting)
    }

    private func opaqueImage(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ImageExportError.creationFailed }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let result = context.makeImage() else { throw ImageExportError.creationFailed }
        return result
    }
}

public enum ImageExportError: LocalizedError, Equatable {
    case singlePageRequired, unsupportedFormat, invalidQuality, creationFailed

    public var errorDescription: String? {
        switch self {
        case .singlePageRequired: "Image formats save one image. Choose PDF to save several pages together."
        case .unsupportedFormat: "Choose JPEG, PNG, or TIFF for image export."
        case .invalidQuality: "JPEG quality must be between zero and one."
        case .creationFailed: "The image could not be saved. Your scans are still available."
        }
    }
}
