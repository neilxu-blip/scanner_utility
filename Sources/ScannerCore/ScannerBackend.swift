import Foundation

/// A completed scan kept in memory until the user finishes the document session.
public struct ScannedPage: Identifiable, Sendable {
    public let id: UUID
    public let imageData: Data

    public init(id: UUID = UUID(), imageData: Data) {
        self.id = id
        self.imageData = imageData
    }
}

public enum ScannerStatus: Equatable, Sendable {
    case warmingUp
    /// nil means acquisition has started but the scanner cannot report a percentage.
    case scanning(progress: Double?)
}

/// Backend implementations acquire one page independently of the UI.
public protocol ScannerBackend: Sendable {
    var displayName: String { get }

    func scanPage(
        number: Int,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScannedPage

    func scanPage(
        number: Int,
        status: @escaping @Sendable (ScannerStatus) async -> Void
    ) async throws -> ScannedPage
}

public extension ScannerBackend {
    /// Fraction-only backends (including the mock) can use the default status bridge.
    func scanPage(
        number: Int,
        status: @escaping @Sendable (ScannerStatus) async -> Void
    ) async throws -> ScannedPage {
        await status(.warmingUp)
        return try await scanPage(number: number) { value in
            if value.isFinite, value > 0 { await status(.scanning(progress: value)) }
        }
    }
}
