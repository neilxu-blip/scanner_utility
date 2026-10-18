import CoreGraphics
import CoreText
import Foundation
import ImageIO

public protocol PDFExporting: Sendable {
    func export(pages: [ScannedPage], to url: URL) throws
}

public enum PDFCompression: String, CaseIterable, Sendable {
    case standard
    case highQuality
    case lossless

    var jpegQuality: Double? {
        switch self {
        case .standard: 0.75
        case .highQuality: 0.9
        case .lossless: nil
        }
    }
}

/// Creates one portrait PDF page per scan at the selected paper size, preserving acquisition order.
public struct PDFExporter: PDFExporting {
    private let compression: PDFCompression
    private let pageSize: CGSize
    private let searchable: Bool
    private let recognitionLanguages: [String]

    public init(
        compression: PDFCompression = .standard, paperSize: ScanPaperSize = .a4,
        searchable: Bool = false, recognitionLanguages: [String] = ["en-US"], pageSize: CGSize? = nil
    ) {
        self.compression = compression
        self.pageSize = pageSize ?? paperSize.pdfSize
        self.searchable = searchable
        self.recognitionLanguages = recognitionLanguages
    }

    public func export(pages: [ScannedPage], to url: URL) throws {
        guard !pages.isEmpty else { throw PDFExportError.noPages }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw PDFExportError.fileAlreadyExists
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw PDFExportError.creationFailed }
        guard pageSize.width.isFinite, pageSize.height.isFinite, pageSize.width > 0, pageSize.height > 0,
              pageSize.width <= 14_400, pageSize.height <= 14_400 else { throw PDFExportError.creationFailed }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFExportError.creationFailed
        }

        do {
            for (index, page) in pages.enumerated() {
                guard let source = CGImageSourceCreateWithData(page.imageData as CFData, nil),
                      let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw PDFExportError.invalidPage(index + 1)
                }
                let image = try imageForPDF(original, pageNumber: index + 1)
                let recognized = searchable ? try ScanTextRecognizer.recognize(page, languages: recognitionLanguages) : []

                context.beginPDFPage(nil)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(mediaBox)
                let scale = min(mediaBox.width / CGFloat(image.width), mediaBox.height / CGFloat(image.height))
                let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                let bounds = CGRect(
                    x: (mediaBox.width - size.width) / 2,
                    y: (mediaBox.height - size.height) / 2,
                    width: size.width,
                    height: size.height
                )
                context.draw(image, in: bounds)
                drawSearchableText(recognized, imageBounds: bounds, in: context)
                context.endPDFPage()
            }
        } catch {
            context.closePDF()
            throw error
        }
        context.closePDF()

        // The exclusive write also protects against a file appearing after the check above.
        try (data as Data).write(to: url, options: .withoutOverwriting)
    }

    private func drawSearchableText(_ recognized: [RecognizedScanText], imageBounds: CGRect, in context: CGContext) {
        for item in recognized {
            let bounds = CGRect(
                x: imageBounds.minX + item.bounds.minX * imageBounds.width,
                y: imageBounds.minY + item.bounds.minY * imageBounds.height,
                width: item.bounds.width * imageBounds.width,
                height: item.bounds.height * imageBounds.height
            )
            guard bounds.width > 0, bounds.height > 0 else { continue }
            // CoreText supplies Unicode font mapping for search/copy, including
            // fallback fonts. Invisible text does not alter the scanned appearance.
            let font = CTFontCreateWithName("Helvetica" as CFString, bounds.height, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: item.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
            ]))
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            guard width > 0, ascent + descent > 0 else { continue }
            context.saveGState()
            context.setTextDrawingMode(.invisible)
            context.textMatrix = CGAffineTransform(scaleX: bounds.width / width, y: bounds.height / (ascent + descent))
            context.textPosition = CGPoint(x: bounds.minX, y: bounds.minY + descent * bounds.height / (ascent + descent))
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    private func imageForPDF(_ original: CGImage, pageNumber: Int) throws -> CGImage {
        guard let quality = compression.jpegQuality else { return original }
        let image = try opaqueImage(original, pageNumber: pageNumber)
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil) else {
            throw PDFExportError.compressionFailed(pageNumber)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: jpeg as CFData),
              let compressed = CGImage(jpegDataProviderSource: provider, decode: nil,
                                       shouldInterpolate: false, intent: .defaultIntent) else {
            throw PDFExportError.compressionFailed(pageNumber)
        }
        // Preserve the JPEG data provider: Quartz embeds the encoded stream in the
        // PDF rather than decoding it back to a large losslessly compressed bitmap.
        // Pixel dimensions are unchanged; no resolution reduction is applied.
        return compressed
    }

    private func opaqueImage(_ image: CGImage, pageNumber: Int) throws -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw PDFExportError.compressionFailed(pageNumber) }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let result = context.makeImage() else { throw PDFExportError.compressionFailed(pageNumber) }
        return result
    }
}

public enum PDFExportError: LocalizedError, Equatable {
    case noPages
    case fileAlreadyExists
    case invalidPage(Int)
    case creationFailed
    case compressionFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .noPages: "There are no scanned pages to save."
        case .fileAlreadyExists: "A file already exists at this location. Choose another name to preserve it."
        case .invalidPage(let number): "Scanned page \(number) could not be read. Your scanned pages are still available."
        case .creationFailed: "The PDF could not be created. Your scanned pages are still available."
        case .compressionFailed(let number): "Scanned page \(number) could not be compressed. Your scanned pages are still available."
        }
    }
}
