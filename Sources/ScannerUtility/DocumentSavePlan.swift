import Foundation
import ScannerCore

/// A save-panel choice remains the base destination; only the requested dated
/// subfolder is added. Constructing a plan never creates files or folders.
struct DocumentSavePlan {
    let url: URL
    let afterSave: AfterSaveAction
    private let baseDirectory: URL
    private let needsDateDirectory: Bool

    init(selectedURL: URL, settings: DocumentSettings, date: Date = Date(), timeZone: TimeZone = .current) {
        baseDirectory = selectedURL.deletingLastPathComponent()
        afterSave = settings.afterSave
        let dateFolder = ScanFilename.dateSubfolder(date: date, timeZone: timeZone)
        needsDateDirectory = settings.useDateSubfolder && baseDirectory.lastPathComponent != dateFolder
        if needsDateDirectory {
            url = baseDirectory.appendingPathComponent(dateFolder, isDirectory: true)
                .appendingPathComponent(selectedURL.lastPathComponent)
        } else {
            url = selectedURL
        }
    }

    /// Called only after the user approves Save, never when opening/canceling a panel.
    func prepareDirectory() throws {
        guard needsDateDirectory else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: baseDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw CocoaError(.fileNoSuchFile) }
        let directory = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw CocoaError(.fileWriteFileExists) }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
    }
}
