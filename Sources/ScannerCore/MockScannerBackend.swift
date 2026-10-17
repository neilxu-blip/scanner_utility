import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Hardware-free scans with reproducible page contents and simulated acquisition progress.
public struct MockScannerBackend: ScannerBackend {
    public let displayName = "Mock Scanner"

    public init() {}

    public func scanPage(
        number: Int,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScannedPage {
        await progress(0)
        try await Task.sleep(for: .milliseconds(600))
        for step in 1...24 {
            try await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            await progress(Double(step) / 25)
        }

        let data = try Self.renderPage(number: number)
        try Task.checkCancellation()
        await progress(1)
        return ScannedPage(imageData: data)
    }

    private static func renderPage(number: Int) throws -> Data {
        let width = 1_240
        let height = 1_754
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MockScanError.renderingFailed
        }

        context.setFillColor(CGColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: height))

        drawText("NORTHSTAR", size: 24, x: 106, y: 1_606, context: context)
        drawText("Project notes", size: 54, x: 102, y: 1_498, context: context)
        drawText("Sample document  /  Page \(number)", size: 24, x: 106, y: 1_440, context: context)
        context.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
        context.setLineWidth(2)
        context.move(to: CGPoint(x: 106, y: 1_396))
        context.addLine(to: CGPoint(x: 1_134, y: 1_396))
        context.strokePath()

        let lines = [
            "DOCUMENT SCANNING WORKFLOW",
            "This is a simulated scan for developing the scanner utility.",
            "Each completed page stays in the current document session.",
            "Choose Scan to add another page in the same order.",
            "Choose Exit to save all completed pages as a single PDF.",
            "",
            "Review notes",
            "Keep page edges aligned before starting the next scan.",
            "Check that text is readable and the page is complete.",
            "The mock scanner does not require connected hardware."
        ]
        for (index, line) in lines.enumerated() {
            drawText(line, size: index == 0 ? 22 : 25, x: 106, y: 1_316 - CGFloat(index) * 54, context: context)
        }

        context.setFillColor(CGColor(gray: 0.94, alpha: 1))
        context.fill(CGRect(x: 106, y: 430, width: 1_028, height: 206))
        drawText("SESSION CHECKLIST", size: 21, x: 134, y: 585, context: context)
        drawText("1. Scan the page   2. Add pages   3. Save one PDF", size: 25, x: 134, y: 526, context: context)
        drawText("Prepared for interface testing", size: 22, x: 106, y: 138, context: context)
        drawText("\(number)", size: 22, x: 1_104, y: 138, context: context)

        guard let image = context.makeImage() else { throw MockScanError.renderingFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw MockScanError.renderingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw MockScanError.renderingFailed }
        return data as Data
    }

    private static func drawText(_ text: String, size: CGFloat, x: CGFloat, y: CGFloat, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.16, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
}

private enum MockScanError: LocalizedError {
    case renderingFailed

    var errorDescription: String? { "The mock scanner could not create its sample page." }
}
