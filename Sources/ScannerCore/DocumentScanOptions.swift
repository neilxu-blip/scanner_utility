import CoreGraphics
import Foundation

/// Acquisition choices are captured when a document session starts so every
/// page in the batch uses the same color, paper geometry, and resolution.
public struct DocumentScanOptions: Equatable, Codable, Sendable {
    public var colorMode: ScanColorMode
    public var paperSize: ScanPaperSize
    public var resolution: ScanResolution
    public var customWidthMillimeters: Double
    public var customHeightMillimeters: Double

    public init(
        colorMode: ScanColorMode = .color,
        paperSize: ScanPaperSize = .a4,
        resolution: ScanResolution = .dpi300,
        customWidthMillimeters: Double = 210,
        customHeightMillimeters: Double = 297
    ) {
        self.colorMode = colorMode
        self.paperSize = paperSize
        self.resolution = resolution
        self.customWidthMillimeters = customWidthMillimeters
        self.customHeightMillimeters = customHeightMillimeters
    }

    public var effectiveWidthMillimeters: Double {
        paperSize == .custom ? customWidthMillimeters : paperSize.widthMillimeters
    }

    public var effectiveHeightMillimeters: Double {
        paperSize == .custom ? customHeightMillimeters : paperSize.heightMillimeters
    }

    public var pdfSize: CGSize {
        paperSize == .custom
            ? CGSize(width: effectiveWidthMillimeters * 72 / 25.4, height: effectiveHeightMillimeters * 72 / 25.4)
            : paperSize.pdfSize
    }

    /// Current flatbed geometry targets the Canon LiDE 120. Validate before
    /// discovery/acquisition so malformed persisted settings cannot move hardware.
    public func validate() throws {
        guard effectiveWidthMillimeters.isFinite, effectiveHeightMillimeters.isFinite,
              (1...216).contains(effectiveWidthMillimeters),
              (1...297).contains(effectiveHeightMillimeters) else {
            throw ScanOptionsError.invalidGeometry
        }
        let widthPixels = ceil(effectiveWidthMillimeters / 25.4 * Double(resolution.rawValue))
        let heightPixels = ceil(effectiveHeightMillimeters / 25.4 * Double(resolution.rawValue))
        let channels = colorMode == .color ? 3.0 : 1.0
        guard widthPixels * heightPixels <= 80_000_000,
              widthPixels * heightPixels * channels <= 134_217_728 else {
            throw ScanOptionsError.imageTooLarge
        }
    }

    private enum CodingKeys: String, CodingKey {
        case colorMode, paperSize, resolution, customWidthMillimeters, customHeightMillimeters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colorMode = try container.decodeIfPresent(ScanColorMode.self, forKey: .colorMode) ?? .color
        paperSize = try container.decodeIfPresent(ScanPaperSize.self, forKey: .paperSize) ?? .a4
        resolution = try container.decodeIfPresent(ScanResolution.self, forKey: .resolution) ?? .dpi300
        customWidthMillimeters = try container.decodeIfPresent(Double.self, forKey: .customWidthMillimeters) ?? 210
        customHeightMillimeters = try container.decodeIfPresent(Double.self, forKey: .customHeightMillimeters) ?? 297
    }
}

public enum ScanColorMode: String, CaseIterable, Codable, Sendable {
    case color
    case grayscale
    case blackAndWhite

    public var displayName: String {
        switch self {
        case .color: "Color"
        case .grayscale: "Grayscale"
        case .blackAndWhite: "Black and White"
        }
    }

    var scanimageMode: String {
        switch self {
        case .color: "Color"
        // Thresholding happens in the native image-processing stage. Gray is
        // supported by the current backend; do not assume a Lineart option.
        case .grayscale, .blackAndWhite: "Gray"
        }
    }
}

public enum ScanPaperSize: String, CaseIterable, Codable, Sendable {
    case a4
    case letter
    case a5
    case b5
    case photo4x6
    case photo5x7
    case custom

    public var displayName: String {
        switch self {
        case .a4: "A4"
        case .letter: "Letter"
        case .a5: "A5"
        case .b5: "B5 (JIS)"
        case .photo4x6: "4 × 6 in"
        case .photo5x7: "5 × 7 in"
        case .custom: "Custom"
        }
    }

    public var widthMillimeters: Double {
        switch self {
        case .a4: 210
        case .letter: 215.9
        case .a5: 148
        case .b5: 182
        case .photo4x6: 101.6
        case .photo5x7: 127
        case .custom: 210
        }
    }

    public var heightMillimeters: Double {
        switch self {
        case .a4: 297
        case .letter: 279.4
        case .a5: 210
        case .b5: 257
        case .photo4x6: 152.4
        case .photo5x7: 177.8
        case .custom: 297
        }
    }

    public var pdfSize: CGSize {
        // Retain the existing A4 box exactly; convert other sizes from mm to
        // PDF points (72 points per inch).
        if self == .a4 { return CGSize(width: 595.276, height: 841.89) }
        return CGSize(width: widthMillimeters * 72 / 25.4, height: heightMillimeters * 72 / 25.4)
    }
}

public enum ScanResolution: Int, CaseIterable, Codable, Sendable {
    case dpi75 = 75
    case dpi100 = 100
    case dpi150 = 150
    case dpi200 = 200
    case dpi300 = 300
    case dpi400 = 400
    case dpi600 = 600
    case dpi1200 = 1_200

    public var displayName: String { "\(rawValue) dpi" }
}

public enum ScanOptionsError: LocalizedError, Equatable {
    case invalidGeometry, imageTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidGeometry: "Choose a scan area between 1 × 1 mm and 216 × 297 mm."
        case .imageTooLarge: "This paper size and resolution exceed the image limit. Choose a lower resolution or smaller scan area."
        }
    }
}
