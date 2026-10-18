import Foundation

public enum ScanFilename {
    /// Save-time timestamp in the user's local time, with filename-safe separators.
    public static func suggested(
        date: Date = Date(), timeZone: TimeZone = .current, prefix: String = "Scanned Document"
    ) -> String {
        "\(sanitizedPrefix(prefix)) \(formatted(date, timeZone: timeZone, format: "yyyy-MM-dd_HH-mm-ss")).pdf"
    }

    /// A prefix is a filename component, never a path. Bound its UTF-8 length to
    /// leave room for the timestamp and extension on common macOS filesystems.
    public static func sanitizedPrefix(_ prefix: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let separated = prefix.components(separatedBy: forbidden).joined(separator: " ")
        let normalized = separated.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var result = ""
        var byteCount = 0
        for character in normalized {
            let count = String(character).utf8.count
            guard byteCount + count <= 180 else { break }
            result.append(character)
            byteCount += count
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return result.isEmpty ? "Scanned Document" : result
    }

    public static func dateSubfolder(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        formatted(date, timeZone: timeZone, format: "yyyy_MM_dd")
    }

    private static func formatted(_ date: Date, timeZone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
