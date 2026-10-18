import AppKit
import Foundation
import ImageIO
import ScannerCore

/// These actions operate on a successfully saved file. They never send an email.
@MainActor
enum PostSaveActions {
    static func perform(url: URL, pages: [ScannedPage], profile: DocumentSettings, general: GeneralSettings) {
        Task {
            do {
                switch profile.afterSave {
                case .none: return
                case .revealInFinder:
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                case .openPreview:
                    guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
                        throw ScanWorkflowError.actionUnavailable
                    }
                    try await open(url, with: application)
                case .openApplication:
                    guard let application = profile.applicationURL else { throw ScanWorkflowError.actionDestinationMissing }
                    let outgoing = try await Task.detached(priority: .userInitiated) {
                        try OutgoingScanImage.url(for: url, general: general)
                    }.value
                    try await open(outgoing, with: application)
                case .copyToFolder:
                    guard let folder = profile.secondaryDirectory else { throw ScanWorkflowError.actionDestinationMissing }
                    let destination = folder.appendingPathComponent(url.lastPathComponent)
                    // Exclusive creation protects an existing destination, including the source itself.
                    try await Task.detached(priority: .userInitiated) {
                        try Data(contentsOf: url).write(to: destination, options: .withoutOverwriting)
                    }.value
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                case .composeEmail:
                    let outgoing = try await Task.detached(priority: .userInitiated) {
                        try OutgoingScanImage.url(for: url, general: general)
                    }.value
                    guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: [outgoing]) else {
                        throw ScanWorkflowError.actionUnavailable
                    }
                    service.perform(withItems: [outgoing])
                case .extractText:
                    let language = general.recognitionLanguage
                    let recognized = try await Task.detached(priority: .userInitiated) {
                        try pages.map { page in
                            try ScanTextRecognizer.recognize(page, languages: language.isEmpty ? [] : [language])
                                .map(\.text).joined(separator: "\n")
                        }.joined(separator: "\n\n")
                    }.value
                    let textURL = url.deletingPathExtension().appendingPathExtension("txt")
                    try Data(recognized.utf8).write(to: textURL, options: .withoutOverwriting)
                    NSWorkspace.shared.open(textURL)
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Scan saved successfully"
                alert.informativeText = "The follow-up action could not finish. \(error.localizedDescription) Your scan remains saved at \(url.path)."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private static func open(_ url: URL, with application: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

enum OutgoingScanImage {
    /// Resize only an outgoing image copy. The saved original and PDF documents are untouched.
    static func url(for savedURL: URL, general: GeneralSettings) throws -> URL {
        guard let maximum = general.sendImageSize.maxPixelDimension,
              ["jpg", "jpeg", "png", "tiff", "tif"].contains(savedURL.pathExtension.lowercased()),
              let source = CGImageSourceCreateWithURL(savedURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximum
              ] as CFDictionary) else { return savedURL }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: general.temporaryDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw CocoaError(.fileNoSuchFile) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            throw ImageExportError.creationFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageExportError.creationFailed }
        let output = general.temporaryDirectory.appendingPathComponent("Scanner-send-\(UUID().uuidString).jpg")
        try (data as Data).write(to: output, options: .withoutOverwriting)
        return output
    }
}
