import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

/// Optional local corrections. Defaults leave the acquired image byte-for-byte intact.
public struct ImageProcessingOptions: Equatable, Codable, Sendable {
    public var autoCrop: Bool
    public var autoEnhance: Bool
    public var sharpen: Bool
    public var reduceShowThrough: Bool
    public var reduceMoire: Bool
    public var reduceGutterShadow: Bool
    public var deskew: Bool
    public var autoRotate: Bool
    public var blackAndWhite: Bool
    public var brightness: Double
    public var contrast: Double
    public var gamma: Double

    public init(
        autoCrop: Bool = false, autoEnhance: Bool = false, sharpen: Bool = false,
        reduceShowThrough: Bool = false, reduceMoire: Bool = false, reduceGutterShadow: Bool = false,
        deskew: Bool = false, autoRotate: Bool = false, blackAndWhite: Bool = false,
        brightness: Double = 0, contrast: Double = 0, gamma: Double = 1
    ) {
        self.autoCrop = autoCrop
        self.autoEnhance = autoEnhance
        self.sharpen = sharpen
        self.reduceShowThrough = reduceShowThrough
        self.reduceMoire = reduceMoire
        self.reduceGutterShadow = reduceGutterShadow
        self.deskew = deskew
        self.autoRotate = autoRotate
        self.blackAndWhite = blackAndWhite
        self.brightness = brightness
        self.contrast = contrast
        self.gamma = gamma
    }
}

public enum ScanItemKind: Sendable {
    case document
    case photo
}

/// Bounds use Vision's normalized image coordinates, with the origin at bottom left.
public struct RecognizedScanText: Sendable {
    public let text: String
    public let bounds: CGRect

    public init(text: String, bounds: CGRect) {
        self.text = text
        self.bounds = bounds
    }
}

public enum ScanTextRecognizer {
    /// Uses the local Vision model. No image or recognized text is sent over a network.
    public static func recognize(
        _ page: ScannedPage, languages: [String] = ["en-US"]
    ) throws -> [RecognizedScanText] {
        try Task.checkCancellation()
        let image = try ScanImageCodec.decode(page)
        let request = try textRequest(languages: languages)
        let analysis = try ScanImageCodec.analysisImage(image)
        try VNImageRequestHandler(cgImage: analysis, orientation: .up).perform([request])
        try Task.checkCancellation()
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.35 else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let bounds = observation.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !text.isEmpty, !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
            return RecognizedScanText(text: text, bounds: bounds)
        }
    }

    fileprivate static func textRequest(languages: [String], accurate: Bool = true) throws -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.005
        let supported = try request.supportedRecognitionLanguages()
        let available = languages.filter { supported.contains($0) }
        request.recognitionLanguages = available.isEmpty ? ["en-US"] : available
        request.automaticallyDetectsLanguage = true
        return request
    }
}

public struct ImageProcessor: Sendable {
    private let options: ImageProcessingOptions
    private let recognitionLanguages: [String]

    public init(options: ImageProcessingOptions = .init(), recognitionLanguages: [String] = ["en-US"]) {
        self.options = options
        self.recognitionLanguages = recognitionLanguages
    }

    public func process(_ page: ScannedPage) throws -> ScannedPage {
        try Task.checkCancellation()
        guard options != ImageProcessingOptions() else { return page }
        return try autoreleasepool {
            let original = try ScanImageCodec.decode(page)
            var image = CIImage(cgImage: original)
            if options.autoRotate {
                image = try correctedOrientation(image, original: original)
            }
            try Task.checkCancellation()
            if options.autoCrop || options.deskew,
               let rendered = ScanImageCodec.context().createCGImage(image, from: image.extent),
               let rectangle = try documentBoundary(in: rendered) {
                if options.autoCrop {
                    let extent = image.extent
                    func vector(_ point: CGPoint) -> CIVector {
                        CIVector(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
                    }
                    image = image.applyingFilter("CIPerspectiveCorrection", parameters: [
                        "inputTopLeft": vector(rectangle.topLeft), "inputTopRight": vector(rectangle.topRight),
                        "inputBottomLeft": vector(rectangle.bottomLeft), "inputBottomRight": vector(rectangle.bottomRight)
                    ])
                } else if options.deskew {
                    let dx = (rectangle.topRight.x - rectangle.topLeft.x) * image.extent.width
                    let dy = (rectangle.topRight.y - rectangle.topLeft.y) * image.extent.height
                    let angle = atan2(dy, dx)
                    // Expand the canvas instead of cutting off the rotated page's corners.
                    if abs(angle) > 0.003, abs(angle) < .pi / 15 {
                        image = image.transformed(by: CGAffineTransform(rotationAngle: -angle))
                    }
                }
            }
            image = translatedToOrigin(image)
            try Task.checkCancellation()
            if options.autoEnhance {
                let filters = image.autoAdjustmentFilters(options: [
                    .enhance: true, .redEye: false, .crop: false, .level: false
                ])
                for filter in filters {
                    try Task.checkCancellation()
                    filter.setValue(image, forKey: kCIInputImageKey)
                    if let result = filter.outputImage { image = result.cropped(to: image.extent) }
                }
            }
            try Task.checkCancellation()
            if options.reduceGutterShadow {
                // Normalize low-frequency illumination. Dark text is retained while broad
                // binding/edge shading is reduced; this is not geometric book dewarping.
                let extent = image.extent
                let background = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: min(80, max(8, extent.width * 0.025))
                ]).cropped(to: extent)
                image = background.applyingFilter("CIDivideBlendMode", parameters: [
                    kCIInputBackgroundImageKey: image
                ]).cropped(to: extent)
            }
            if options.reduceShowThrough {
                image = image.applyingFilter("CIToneCurve", parameters: [
                    "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0.25, y: 0.22),
                    "inputPoint2": CIVector(x: 0.5, y: 0.58), "inputPoint3": CIVector(x: 0.75, y: 0.9),
                    "inputPoint4": CIVector(x: 1, y: 1)
                ])
            }
            if options.reduceMoire {
                let extent = image.extent
                image = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.04, "inputSharpness": 0])
                    .clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.6])
                    .cropped(to: extent)
            }
            if options.sharpen {
                image = image.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 1.5, kCIInputIntensityKey: 0.6])
            }
            try Task.checkCancellation()
            let brightness = finite(options.brightness, default: 0, range: -1...1)
            let contrast = finite(options.contrast, default: 0, range: -1...1)
            let gamma = finite(options.gamma, default: 1, range: 0.1...3)
            if brightness != 0 || contrast != 0 {
                image = image.applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: brightness, kCIInputContrastKey: 1 + contrast
                ])
            }
            if gamma != 1 { image = image.applyingFilter("CIGammaAdjust", parameters: ["inputPower": gamma]) }
            if options.blackAndWhite {
                image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
                    .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.5])
            }
            let extent = image.extent.integral
            guard !extent.isInfinite, !extent.isNull, extent.width > 0, extent.height > 0,
                  extent.width * extent.height <= ScanImageCodec.maximumPixels else {
                throw ImageProcessingError.imageTooLarge
            }
            let white = CIImage(color: CIColor.white).cropped(to: extent)
            image = image.composited(over: white)
            guard let result = ScanImageCodec.context().createCGImage(image, from: extent) else {
                throw ImageProcessingError.processingFailed
            }
            try Task.checkCancellation()
            let data = try ScanImageCodec.png(result, original: page)
            try Task.checkCancellation()
            return ScannedPage(id: page.id, imageData: data)
        }
    }

    /// A conservative native substitute for Canon's proprietary Auto Scan classifier.
    /// Text-rich pages are documents; other originals are photos. Handwriting and
    /// sparse/unsupported-language pages may need an explicit user-selected mode.
    public static func classify(_ page: ScannedPage, languages: [String] = ["en-US"]) throws -> ScanItemKind {
        let text = try ScanTextRecognizer.recognize(page, languages: languages)
        let characters = text.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count }
        let area = text.reduce(CGFloat.zero) { $0 + $1.bounds.width * $1.bounds.height }
        return (text.count >= 3 && characters >= 35) || (characters >= 80 && area >= 0.015) ? .document : .photo
    }

    private func documentBoundary(in image: CGImage) throws -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.85
        request.minimumSize = 0.35
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1
        request.quadratureTolerance = 20
        request.maximumObservations = 4
        let analysis = try ScanImageCodec.analysisImage(image)
        try VNImageRequestHandler(cgImage: analysis, orientation: .up).perform([request])
        try Task.checkCancellation()
        return (request.results ?? []).filter { rectangle in
            rectangle.confidence >= 0.85 && rectangle.boundingBox.width * rectangle.boundingBox.height >= 0.25
        }.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
    }

    private func correctedOrientation(_ image: CIImage, original: CGImage) throws -> CIImage {
        let analysis = try ScanImageCodec.analysisImage(original)
        var scores: [(CGImagePropertyOrientation, Double)] = []
        for orientation: CGImagePropertyOrientation in [.up, .right, .down, .left] {
            try Task.checkCancellation()
            // Accurate recognition supports the same selected languages as PDF OCR.
            let request = try ScanTextRecognizer.textRequest(languages: recognitionLanguages)
            try VNImageRequestHandler(cgImage: analysis, orientation: orientation).perform([request])
            try Task.checkCancellation()
            let swapsAxes = orientation == .left || orientation == .right
            let width = CGFloat(swapsAxes ? analysis.height : analysis.width)
            let height = CGFloat(swapsAxes ? analysis.width : analysis.height)
            let score = (request.results ?? []).reduce(0.0) { total, observation in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.5 else { return total }
                // Accurate Vision can read sideways and upside-down lines with the
                // same confidence as upright ones. Its quadrilateral still records
                // the text's reading direction, unlike its axis-aligned bounding box.
                let baseline = CGVector(
                    dx: (observation.topRight.x - observation.topLeft.x) * width,
                    dy: (observation.topRight.y - observation.topLeft.y) * height
                )
                let upright = CGVector(
                    dx: (observation.topLeft.x - observation.bottomLeft.x) * width,
                    dy: (observation.topLeft.y - observation.bottomLeft.y) * height
                )
                let baselineLength = hypot(baseline.dx, baseline.dy)
                let uprightLength = hypot(upright.dx, upright.dy)
                guard baselineLength > 0, uprightLength > 0 else { return total }
                let directionWeight = max(0, baseline.dx / baselineLength) * max(0, upright.dy / uprightLength)
                return total + Double(min(candidate.string.count, 120)) * Double(candidate.confidence) * Double(directionWeight)
            }
            scores.append((orientation, score))
        }
        guard let uprightScore = scores.first?.1,
              let best = scores.max(by: { $0.1 < $1.1 }), best.0 != .up,
              best.1 >= 12, best.1 > max(uprightScore * 1.35, uprightScore + 8) else { return image }
        return translatedToOrigin(image.oriented(best.0))
    }

    private func translatedToOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    private func finite(_ value: Double, default fallback: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

public enum ImageProcessingError: LocalizedError {
    case invalidImage
    case imageTooLarge
    case processingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage: "The scanned image could not be read."
        case .imageTooLarge: "The image is too large to process safely. Try a lower scanning resolution."
        case .processingFailed: "The image could not be processed. Try scanning with image corrections disabled."
        }
    }
}

private enum ScanImageCodec {
    // Full-resolution filters remain bounded; OCR/detection use a smaller analysis copy.
    static let maximumPixels: CGFloat = 80_000_000

    static func context() -> CIContext { CIContext(options: [.cacheIntermediates: false]) }

    static func decode(_ page: ScannedPage) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(page.imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ImageProcessingError.invalidImage
        }
        guard width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= Double(maximumPixels) else {
            throw ImageProcessingError.imageTooLarge
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImageProcessingError.invalidImage }
        return image
    }

    static func analysisImage(_ original: CGImage) throws -> CGImage {
        let limit = CGFloat(2_600)
        let longest = CGFloat(max(original.width, original.height))
        guard longest > limit else { return original }
        let image = CIImage(cgImage: original).transformed(by: CGAffineTransform(scaleX: limit / longest, y: limit / longest))
        guard let result = context().createCGImage(image, from: image.extent.integral) else {
            throw ImageProcessingError.processingFailed
        }
        return result
    }

    static func png(_ image: CGImage, original: ScannedPage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw ImageProcessingError.processingFailed
        }
        var metadata: [CFString: Any] = [:]
        if let source = CGImageSourceCreateWithData(original.imageData as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let width = properties[kCGImagePropertyDPIWidth] { metadata[kCGImagePropertyDPIWidth] = width }
            if let height = properties[kCGImagePropertyDPIHeight] { metadata[kCGImagePropertyDPIHeight] = height }
        }
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.processingFailed }
        return data as Data
    }
}
