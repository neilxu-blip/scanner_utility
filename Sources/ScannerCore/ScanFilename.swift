import Foundation

public enum ScanFilename {
    /// Save-time timestamp in the user's local time, with filename-safe separators.
    public static func suggested(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Scanned Document \(formatter.string(from: date)).pdf"
    }
}
