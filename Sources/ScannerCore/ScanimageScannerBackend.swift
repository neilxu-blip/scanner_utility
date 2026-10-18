import Foundation
import ImageIO

public struct SANEDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ScanimageClient: Sendable {
    public let executable: URL
    let runner: any ScanimageRunning

    public init(executable: URL, runner: any ScanimageRunning = ScanimageProcess()) {
        self.executable = executable
        self.runner = runner
    }

    public static func findExecutable() -> URL? {
        let candidates = ["/opt/homebrew/bin/scanimage", "/usr/local/bin/scanimage"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/scanimage" }
        return candidates.first { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Enumeration only: this command never acquires an image.
    public func devices() async throws -> [SANEDevice] {
        let result = try await runner.run(
            executable: executable, arguments: ["--formatted-device-list=%d\t%v\t%m%n"],
            timeout: 20, onDiagnostic: { _ in }
        )
        try Task.checkCancellation()
        guard result.exitCode == 0 else { throw ScanimageError.commandFailed(result.diagnostic) }
        return Self.parseDevices(result.output)
    }

    /// USB addresses may change after a scan resets the device. Keep the selected
    /// model/backend, but resolve its current address before every acquisition.
    func currentDevice(matching selected: SANEDevice) async throws -> SANEDevice {
        let backend = selected.id.split(separator: ":", maxSplits: 1).first
        let matches = try await devices().filter {
            $0.name == selected.name && $0.id.split(separator: ":", maxSplits: 1).first == backend
        }
        if let exact = matches.first(where: { $0.id == selected.id }) { return exact }
        guard !matches.isEmpty else { throw ScanimageError.deviceUnavailable(selected.name) }
        guard matches.count == 1 else { throw ScanimageError.ambiguousDevice(selected.name) }
        return matches[0]
    }

    static func parseDevices(_ data: Data) -> [SANEDevice] {
        var seen = Set<String>()
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, !fields[0].isEmpty else { return nil }
            let id = String(fields[0])
            guard seen.insert(id).inserted else { return nil }
            let name = fields.dropFirst().map(String.init).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return SANEDevice(id: id, name: name.isEmpty ? id : name)
        }
    }
}

/// Acquires one flatbed page. The caller must obtain approval before invoking this backend.
public struct ScanimageScannerBackend: ScannerBackend {
    public var displayName: String { device.name }
    public let device: SANEDevice
    private let client: ScanimageClient
    private let options: DocumentScanOptions

    public init(client: ScanimageClient, device: SANEDevice, options: DocumentScanOptions = .init()) {
        self.client = client
        self.device = device
        self.options = options
    }

    public func scanPage(
        number: Int, progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScannedPage {
        try await scanPage(number: number, status: { status in
            switch status {
            case .warmingUp: await progress(0)
            case .scanning(let value):
                if let value { await progress(value) }
            }
        })
    }

    public func scanPage(
        number: Int, status: @escaping @Sendable (ScannerStatus) async -> Void
    ) async throws -> ScannedPage {
        try options.validate()
        let (updates, continuation) = AsyncStream<ScannerStatus>.makeStream()
        let parser = ScanimageProgressParser()
        let reporting = Task {
            for await value in updates { await status(value) }
        }
        await status(.warmingUp)
        do {
            let current = try await client.currentDevice(matching: device)
            var result = try await acquire(current, parser: parser, continuation: continuation)
            // The device can also re-enumerate between discovery and open. Retry
            // once only if open failed, the address changed, and acquisition never
            // started. Never retry a partial scan or append duplicate pages.
            if result.exitCode != 0, result.output.isEmpty, !parser.hasReportedAcquisition,
               result.diagnostic.contains("open of device \(current.id) failed:") {
                let refreshed = try await client.currentDevice(matching: device)
                if refreshed.id != current.id {
                    result = try await acquire(refreshed, parser: parser, continuation: continuation)
                }
            }
            continuation.finish()
            await reporting.value
            try Task.checkCancellation()
            guard result.exitCode == 0 else { throw ScanimageError.commandFailed(result.diagnostic) }
            guard let source = CGImageSourceCreateWithData(result.output as CFData, nil),
                  CGImageSourceGetStatus(source) == .statusComplete,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw ScanimageError.invalidImage
            }
            await status(.scanning(progress: 1))
            return ScannedPage(imageData: result.output)
        } catch {
            continuation.finish()
            await reporting.value
            throw error
        }
    }

    private func acquire(
        _ current: SANEDevice, parser: ScanimageProgressParser,
        continuation: AsyncStream<ScannerStatus>.Continuation
    ) async throws -> ScanimageResult {
        try Task.checkCancellation()
        return try await client.runner.run(
            executable: client.executable,
            arguments: ["--device-name=\(current.id)", "--format=png", "--progress",
                        "--mode=\(options.colorMode.scanimageMode)",
                        "--resolution=\(options.resolution.rawValue)", "--depth=8",
                        "-l", "0", "-t", "0", "-x", millimeters(options.effectiveWidthMillimeters),
                        "-y", millimeters(options.effectiveHeightMillimeters)],
            timeout: 300,
            onDiagnostic: { bytes in
                for value in parser.appendStatuses(bytes) { continuation.yield(value) }
            }
        )
    }

    private func millimeters(_ value: Double) -> String {
        // scanimage expects a dot regardless of the user's locale. Avoid a
        // decimal suffix for integral dimensions to keep existing commands stable.
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

/// scanimage writes percentages to stderr with carriage returns, possibly split across reads.
final class ScanimageProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var acquisitionReported = false
    private let expression = try! NSRegularExpression(pattern: #"Progress:\s*(?:([0-9]+(?:\.[0-9]+)?)%|\(unknown\))"#)

    var hasReportedAcquisition: Bool { lock.withLock { acquisitionReported } }

    func append(_ data: Data) -> [Double] {
        appendStatuses(data).compactMap {
            if case .scanning(let value) = $0 { return value }
            return nil
        }
    }

    func appendStatuses(_ data: Data) -> [ScannerStatus] {
        lock.withLock {
            pending += String(decoding: data, as: UTF8.self)
            let text = pending as NSString
            let matches = expression.matches(in: pending, range: NSRange(location: 0, length: text.length))
            let values = matches.compactMap { match -> ScannerStatus? in
                if match.range(at: 1).location == NSNotFound { return .scanning(progress: nil) }
                guard let value = Double(text.substring(with: match.range(at: 1))), value.isFinite else { return nil }
                return .scanning(progress: min(max(value / 100, 0), 1))
            }
            if !values.isEmpty { acquisitionReported = true }
            if let last = matches.last { pending = text.substring(from: NSMaxRange(last.range)) }
            if pending.count > 4_096 { pending = String(pending.suffix(4_096)) }
            return values
        }
    }
}

public enum ScanimageError: LocalizedError {
    case commandFailed(String)
    case timedOut
    case invalidImage
    case outputTooLarge
    case deviceUnavailable(String)
    case ambiguousDevice(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            let detail = message.components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("Progress:") && !$0.isEmpty }.joined(separator: " ")
            return "SANE could not complete the request. " +
                (detail.isEmpty ? "Check the USB connection and close other scanner applications, then try again." : String(detail.suffix(1_000)))
        case .timedOut:
            return "The scanner did not respond in time. Check the USB connection, close other scanner applications, and try again."
        case .invalidImage:
            return "The scanner did not return a complete image. Earlier pages are still available; try scanning this page again."
        case .outputTooLarge:
            return "The scan exceeded the supported image size. Earlier pages are still available."
        case .deviceUnavailable(let name):
            return "\(name) is not available. Check its USB connection, wait a moment, then click Scan to try again. Your completed pages are still in this document."
        case .ambiguousDevice(let name):
            return "More than one \(name) was found after its USB address changed. Disconnect the extra matching scanners, then click Scan. Your completed pages are still in this document."
        }
    }
}
