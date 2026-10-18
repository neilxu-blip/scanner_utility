import CoreGraphics
import Foundation
import ImageIO

/// Joins two aligned scans in their acquisition order. The overlap is a manual
/// fraction of the shorter edge along the join; this does not register images
/// or infer their position from content.
public enum ImageStitcher {
    public static func stitch(
        _ first: ScannedPage, _ second: ScannedPage,
        direction: StitchDirection = .horizontal, overlap: Double = 0.15
    ) throws -> ScannedPage {
        try Task.checkCancellation()
        guard overlap.isFinite, (0...0.5).contains(overlap) else {
            throw ImageStitchError.invalidOverlap
        }
        let firstSource = try source(first)
        let secondSource = try source(second)
        let firstSize = try dimensions(firstSource)
        let secondSize = try dimensions(secondSource)
        let horizontal = direction == .horizontal
        guard horizontal ? firstSize.height == secondSize.height : firstSize.width == secondSize.width else {
            throw ImageStitchError.incompatibleDimensions
        }
        let firstLength = horizontal ? firstSize.width : firstSize.height
        let secondLength = horizontal ? secondSize.width : secondSize.height
        let overlapPixels = Int((Double(min(firstLength, secondLength)) * overlap).rounded())
        let offset = firstLength - overlapPixels
        let width = horizontal ? offset + secondSize.width : firstSize.width
        let height = horizontal ? firstSize.height : offset + secondSize.height
        // Bound every decoded buffer before decoding. Two input buffers plus
        // the result must fit within a 256 MiB bitmap budget. Higher-resolution
        // scans can be joined after selecting a lower acquisition resolution.
        let bitmapPixels = firstSize.width * firstSize.height + secondSize.width * secondSize.height + width * height
        guard width <= 32_768, height <= 32_768, bitmapPixels <= 67_108_864 else {
            throw ImageStitchError.imageTooLarge
        }
        try Task.checkCancellation()
        guard let firstImage = CGImageSourceCreateImageAtIndex(firstSource, 0, nil),
              let secondImage = CGImageSourceCreateImageAtIndex(secondSource, 0, nil) else {
            throw ImageStitchError.invalidImage
        }
        let firstBitmap = try bitmap(firstImage)
        let secondBitmap = try bitmap(secondImage)
        let resultBitmap = try makeBitmap(width: width, height: height)
        guard let firstPixels = firstBitmap.data?.assumingMemoryBound(to: UInt8.self),
              let secondPixels = secondBitmap.data?.assumingMemoryBound(to: UInt8.self),
              let output = resultBitmap.data?.assumingMemoryBound(to: UInt8.self) else {
            throw ImageStitchError.creationFailed
        }

        for row in 0..<firstSize.height {
            try Task.checkCancellation()
            output.advanced(by: row * width * 4).update(
                from: firstPixels.advanced(by: row * firstSize.width * 4), count: firstSize.width * 4
            )
        }
        for row in 0..<secondSize.height {
            try Task.checkCancellation()
            for column in 0..<secondSize.width {
                let axis = horizontal ? column : row
                let resultX = horizontal ? column + offset : column
                let resultY = horizontal ? row : row + offset
                let resultIndex = (resultY * width + resultX) * 4
                let secondIndex = (row * secondSize.width + column) * 4
                if axis < overlapPixels {
                    let firstX = horizontal ? column + offset : column
                    let firstY = horizontal ? row : row + offset
                    let firstIndex = (firstY * firstSize.width + firstX) * 4
                    let weight = Double(axis + 1) / Double(overlapPixels + 1)
                    for channel in 0..<3 {
                        output[resultIndex + channel] = UInt8((
                            Double(firstPixels[firstIndex + channel]) * (1 - weight) +
                            Double(secondPixels[secondIndex + channel]) * weight
                        ).rounded())
                    }
                } else {
                    output[resultIndex] = secondPixels[secondIndex]
                    output[resultIndex + 1] = secondPixels[secondIndex + 1]
                    output[resultIndex + 2] = secondPixels[secondIndex + 2]
                }
                output[resultIndex + 3] = 255
            }
        }
        guard let image = resultBitmap.makeImage() else { throw ImageStitchError.creationFailed }
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw ImageStitchError.creationFailed
        }
        // The joined image has the same acquisition pixel density as its parts.
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(firstSource, 0, nil) as? [CFString: Any] ?? [:]
        var properties: [CFString: Any] = [:]
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            properties[key] = sourceProperties[key]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageStitchError.creationFailed }
        return ScannedPage(imageData: data as Data)
    }

    private static func source(_ page: ScannedPage) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(page.imageData as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete else {
            throw ImageStitchError.invalidImage
        }
        return source
    }

    private static func dimensions(_ source: CGImageSource) throws -> (width: Int, height: Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32_768, height <= 32_768 else {
            throw ImageStitchError.imageTooLarge
        }
        return (width, height)
    }

    private static func makeBitmap(width: Int, height: Int) throws -> CGContext {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ImageStitchError.creationFailed }
        return context
    }

    private static func bitmap(_ image: CGImage) throws -> CGContext {
        let context = try makeBitmap(width: image.width, height: image.height)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context
    }
}

public enum ImageStitchError: LocalizedError, Equatable {
    case invalidOverlap, invalidImage, incompatibleDimensions, imageTooLarge, creationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidOverlap: "Overlap must be between 0% and 50%."
        case .invalidImage: "One of the scans could not be read. Your original scans are still available."
        case .incompatibleDimensions: "Use the same paper size and resolution for both scans before joining them."
        case .imageTooLarge: "These scans are too large to join in memory. Select a lower resolution and scan again."
        case .creationFailed: "The scans could not be joined. Your original scans are still available."
        }
    }
}
