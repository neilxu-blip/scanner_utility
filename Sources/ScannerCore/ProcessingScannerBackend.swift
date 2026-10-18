import Foundation

/// The same local image pipeline is applied to mock and SANE acquisitions.
public struct ProcessingScannerBackend: ScannerBackend {
    private let backend: any ScannerBackend
    private let processor: ImageProcessor
    public var displayName: String { backend.displayName }

    public init(backend: any ScannerBackend, processor: ImageProcessor) {
        self.backend = backend
        self.processor = processor
    }

    public func scanPage(number: Int, progress: @escaping @Sendable (Double) async -> Void) async throws -> ScannedPage {
        try await scanPage(number: number, status: { value in
            if case .scanning(let progressValue) = value, let progressValue { await progress(progressValue) }
        })
    }

    public func scanPage(number: Int, status: @escaping @Sendable (ScannerStatus) async -> Void) async throws -> ScannedPage {
        let page = try await backend.scanPage(number: number, status: status)
        try Task.checkCancellation()
        let processor = processor
        let processing = Task.detached(priority: .userInitiated) { try processor.process(page) }
        let result = try await withTaskCancellationHandler {
            try await processing.value
        } onCancel: {
            processing.cancel()
        }
        try Task.checkCancellation()
        return result
    }
}
