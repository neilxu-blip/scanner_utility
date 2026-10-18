import CoreImage
import Foundation
import ImageIO

public enum ScanPageEditing {
    public static func rotateClockwise(_ page: ScannedPage) throws -> ScannedPage {
        guard let source = CGImageSourceCreateWithData(page.imageData as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PDFExportError.invalidPage(1)
        }
        let rotated = CIImage(cgImage: original).oriented(.right)
        guard let image = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(rotated, from: rotated.extent) else {
            throw ImageExportError.creationFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw ImageExportError.creationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageExportError.creationFailed }
        return ScannedPage(id: page.id, imageData: data as Data)
    }
}
