import Combine
import Foundation

public enum DocumentPhase: Equatable, Sendable {
    case idle
    case scanning
    case ready
    case exporting
    case saved
}

/// Owns the current in-memory document; only an explicit export creates a PDF.
@MainActor
public final class DocumentSession: ObservableObject {
    @Published public private(set) var phase: DocumentPhase = .idle
    @Published public private(set) var pages: [ScannedPage] = []
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var scanStatus: ScannerStatus = .warmingUp
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var savedURL: URL?
    @Published public private(set) var scannerDisplayName: String

    private var backend: any ScannerBackend
    private var exporter: any PDFExporting
    private var scanTask: Task<Void, Never>?
    private var scanID: UUID?

    public init(backend: any ScannerBackend, exporter: any PDFExporting = PDFExporter()) {
        self.backend = backend
        self.exporter = exporter
        self.scannerDisplayName = backend.displayName
    }

    /// A document keeps the same scanner until it has been saved or has no pages.
    @discardableResult
    public func selectBackend(_ backend: any ScannerBackend, exporter: (any PDFExporting)? = nil) -> Bool {
        guard phase == .idle || phase == .saved else { return false }
        self.backend = backend
        if let exporter { self.exporter = exporter }
        scannerDisplayName = backend.displayName
        errorMessage = nil
        return true
    }

    public func start() {
        guard phase == .idle || phase == .saved else { return }
        pages = []
        savedURL = nil
        beginScan()
    }

    public func scanNext() {
        guard phase == .ready else { return }
        beginScan()
    }

    public func cancelScan() {
        guard phase == .scanning else { return }
        scanID = nil
        scanTask?.cancel()
        scanTask = nil
        progress = 0
        scanStatus = .warmingUp
        phase = pages.isEmpty ? .idle : .ready
    }

    public func export(to url: URL, exporter exportOverride: (any PDFExporting)? = nil) async {
        guard phase == .ready, !pages.isEmpty else { return }
        phase = .exporting
        errorMessage = nil
        let exportPages = pages
        let exporter = exportOverride ?? exporter

        do {
            try await Task.detached(priority: .userInitiated) {
                try exporter.export(pages: exportPages, to: url)
            }.value
            savedURL = url
            phase = .saved
        } catch {
            errorMessage = error.localizedDescription
            phase = .ready
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    /// Explicit review actions edit only this in-memory batch, never source files.
    public func replacePage(id: UUID, with page: ScannedPage) {
        guard phase == .ready, let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index] = page
    }

    public func movePage(id: UUID, by offset: Int) {
        guard phase == .ready, (-1...1).contains(offset), let index = pages.firstIndex(where: { $0.id == id }),
              pages.indices.contains(index + offset) else { return }
        pages.swapAt(index, index + offset)
    }

    public func removePage(id: UUID) {
        guard phase == .ready else { return }
        pages.removeAll { $0.id == id }
        if pages.isEmpty { phase = .idle }
    }

    /// The UI requires an explicit discard confirmation before calling this.
    public func discard() {
        guard phase == .ready || phase == .idle else { return }
        pages = []
        errorMessage = nil
        phase = .idle
    }

    private func beginScan() {
        let id = UUID()
        let number = pages.count + 1
        let backend = backend
        scanID = id
        errorMessage = nil
        progress = 0
        scanStatus = .warmingUp
        phase = .scanning

        scanTask = Task { [weak self] in
            do {
                let page = try await backend.scanPage(number: number, status: { [weak self] value in
                    await self?.updateStatus(value, scanID: id)
                })
                try Task.checkCancellation()
                guard let self, self.scanID == id else { return }
                self.pages.append(page)
                self.progress = 1
                self.scanStatus = .scanning(progress: 1)
                self.phase = .ready
                self.scanID = nil
                self.scanTask = nil
            } catch {
                guard let self, self.scanID == id else { return }
                if !(error is CancellationError) {
                    self.errorMessage = error.localizedDescription
                }
                self.progress = 0
                self.scanStatus = .warmingUp
                self.phase = self.pages.isEmpty ? .idle : .ready
                self.scanID = nil
                self.scanTask = nil
            }
        }
    }

    private func updateStatus(_ status: ScannerStatus, scanID id: UUID) {
        guard scanID == id, phase == .scanning else { return }
        switch status {
        case .warmingUp:
            // A delayed preparation event must not replace acquisition progress.
            break
        case .scanning(let value):
            if let value {
                guard value.isFinite else { return }
                progress = max(progress, min(max(value, 0), 1))
                scanStatus = .scanning(progress: progress)
            } else if progress == 0 {
                scanStatus = .scanning(progress: nil)
            }
        }
    }

    deinit {
        scanTask?.cancel()
    }
}
