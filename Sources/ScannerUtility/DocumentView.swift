import AppKit
import ScannerCore
import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {
    @ObservedObject var session: DocumentSession
    let settingsStore: DocumentSettingsStore
    let mode: ScanWorkflowMode
    let profile: DocumentSettings
    var onClose: () -> Void
    @State private var showingSavePanel = false
    @State private var saveError: String?
    @State private var preparedPreview: ScannedPage?
    @State private var detectedFormat: ScanOutputFormat?
    @State private var isPreparing = false
    @State private var isEditing = false
    @State private var editingRevision = 0
    @State private var selectedPageID: UUID?
    @State private var removingPageID: UUID?
    @State private var showingRemoveConfirmation = false
    @State private var stitchOverlap = 0.15
    @State private var stitchDirection = StitchDirection.horizontal
    @State private var pendingSaveProfile: DocumentSettings?
    @State private var pendingGeneral = GeneralSettings()
    @State private var showingDiscardConfirmation = false
    @State private var manualOutput = false

    private var scanning: Bool { session.phase == .scanning }
    private var warmingUp: Bool { scanning && session.scanStatus == .warmingUp }
    private var acquisitionProgress: Double? {
        if case .scanning(let value) = session.scanStatus { return value }
        return nil
    }
    private var format: ScanOutputFormat? {
        profile.outputFormat == .automatic ? detectedFormat : profile.outputFormat
    }
    private var canAppend: Bool {
        mode == .stitch ? session.pages.count < 2 : (profile.outputFormat == .pdf && mode != .auto)
    }
    private var canSave: Bool {
        !session.pages.isEmpty && format != nil && !isPreparing && !isEditing &&
            (mode != .stitch || (session.pages.count == 2 && preparedPreview != nil))
    }
    private var selectedPage: ScannedPage? {
        session.pages.first { $0.id == selectedPageID } ?? session.pages.last
    }
    private var preparationID: String {
        "\(session.phase)-\(session.pages.map { $0.id.uuidString }.joined())-\(editingRevision)-\(stitchDirection.rawValue)-\(stitchOverlap)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: scanning ? "scanner" : mode.symbol)
                    .font(.system(size: 25))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    Text("\(mode.displayName) · \(profile.scanOptions.paperSize.displayName) · \(profile.scanOptions.resolution.displayName)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if scanning {
                acquisitionView
            } else if session.phase == .exporting {
                ProgressView("Saving scanned output…")
            } else if session.phase == .ready {
                readyView
            } else {
                Text(session.errorMessage == nil ? "No completed scan is available. You can try again." : "The scan did not finish. Earlier completed images remain available.")
                    .foregroundStyle(.secondary)
            }

            if let error = saveError ?? session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Text(session.scannerDisplayName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if scanning {
                    Button("Cancel") {
                        session.cancelScan()
                        if session.pages.isEmpty { onClose() }
                    }.keyboardShortcut(.cancelAction)
                } else if session.phase == .ready {
                    Button("Discard…") { showingDiscardConfirmation = true }
                        .disabled(showingSavePanel || isEditing)
                    if canAppend {
                        Button(mode == .stitch ? "Scan second half" : "Scan") {
                            saveError = nil
                            session.scanNext()
                        }
                        .disabled(showingSavePanel || isPreparing || isEditing)
                    }
                    Button(mode == .document ? "Exit" : "Save…") { chooseDestination() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(showingSavePanel || !canSave)
                } else if session.phase == .idle {
                    Button("Close", action: onClose)
                    Button("Try Again") { session.start() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(26)
        .frame(width: 600)
        .interactiveDismissDisabled()
        .onAppear {
            stitchOverlap = profile.stitchOverlap
            stitchDirection = profile.stitchDirection
        }
        .task(id: preparationID) { await preparePreview() }
        .onChange(of: session.phase) { _, phase in
            if phase == .saved {
                if let url = session.savedURL, let settings = pendingSaveProfile {
                    let pages = mode == .stitch ? preparedPreview.map { [$0] } ?? session.pages : session.pages
                    PostSaveActions.perform(url: url, pages: pages, profile: settings, general: pendingGeneral)
                }
                onClose()
            }
        }
        .confirmationDialog("Remove this unsaved page from the session?", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove page", role: .destructive) {
                if let id = removingPageID { session.removePage(id: id) }
                removingPageID = nil
            }
            Button("Cancel", role: .cancel) { removingPageID = nil }
        }
        .confirmationDialog("Discard these unsaved scans?", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard scans", role: .destructive) {
                session.discard()
                onClose()
            }
            Button("Keep scans", role: .cancel) {}
        } message: {
            Text("This clears the current in-memory session. Files already saved on disk are untouched.")
        }
    }

    private var acquisitionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if warmingUp {
                ProgressView("Warming up for \(mode == .stitch ? "half" : "page") \(session.pages.count + 1)…")
                Text("Keep the document cover closed. Scanning begins after preparation.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let value = acquisitionProgress {
                HStack {
                    Text(value >= 1 ? "Finishing acquisition and image processing…" : "Scanning…")
                    Spacer()
                    Text(value, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
                ProgressView(value: value, total: 1).progressViewStyle(.linear)
            } else {
                ProgressView("Scanning…")
                Text("The scanner cannot report a progress percentage.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                ScanThumbnail(page: mode == .stitch ? preparedPreview ?? session.pages.last : selectedPage)
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(session.pages.count) completed \(session.pages.count == 1 ? "scan" : "scans")", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if mode == .stitch {
                        Text(session.pages.count == 1
                             ? "Move the original to scan its second half. Keep an overlapping strip containing the same detail, in the selected direction."
                             : "Review the join. Adjust direction and overlap before saving.")
                    } else if canAppend {
                        Text("Place the next page and click Scan. Choose Exit or Save when all pages are ready.")
                    } else {
                        Text("Review this image, then choose Save. Start another scan from the main window after saving.")
                    }
                    if let format {
                        Text("Output: \(format.displayName)").font(.callout).foregroundStyle(.secondary)
                    }
                    if isPreparing { ProgressView("Preparing preview…").controlSize(.small) }
                    if mode == .auto {
                        Text("Auto uses local text detection to choose PDF or JPEG. Check the result; use Photo or Document for an explicit choice.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if mode == .stitch {
                Picker("Join direction", selection: $stitchDirection) {
                    ForEach(StitchDirection.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                HStack {
                    Text("Overlap \(Int(stitchOverlap * 100))%")
                    Slider(value: $stitchOverlap, in: 0...0.5, step: 0.05)
                }
                Text("Manual overlap join with a blended seam. Align the halves carefully; automatic feature alignment is not used.")
                    .font(.caption).foregroundStyle(.secondary)
                if session.pages.count == 2 {
                    Button("Retake second half…") {
                        removingPageID = session.pages.last?.id
                        showingRemoveConfirmation = true
                    }
                        .disabled(showingSavePanel || isPreparing)
                }
            } else if profile.checkScanResults {
                HStack {
                    if session.pages.count > 1 {
                        Picker("Review page", selection: Binding(
                            get: { selectedPage?.id ?? UUID() }, set: { selectedPageID = $0 }
                        )) {
                            ForEach(Array(session.pages.enumerated()), id: \.element.id) { index, page in
                                Text("Page \(index + 1)").tag(page.id)
                            }
                        }
                        .frame(maxWidth: 170)
                        Button("Earlier") { if let page = selectedPage { session.movePage(id: page.id, by: -1) } }
                        Button("Later") { if let page = selectedPage { session.movePage(id: page.id, by: 1) } }
                    }
                    Button("Rotate") { rotateSelectedPage() }
                    Button("Remove…") {
                        removingPageID = selectedPage?.id
                        showingRemoveConfirmation = true
                    }
                }
                .disabled(isPreparing || isEditing || showingSavePanel)
            }
            if profile.outputFormat == .automatic {
                Picker("Save as", selection: Binding(
                    get: { detectedFormat ?? .pdf },
                    set: { detectedFormat = $0; manualOutput = true }
                )) {
                    Text("PDF").tag(ScanOutputFormat.pdf)
                    Text("JPEG").tag(ScanOutputFormat.jpeg)
                }
                .disabled(isPreparing || showingSavePanel)
            }
        }
    }

    private var title: String {
        switch session.phase {
        case .scanning: warmingUp ? "Warming up…" : "Scanning…"
        case .exporting: "Saving scan…"
        case .ready: "Scan complete"
        case .idle: "Scan stopped"
        case .saved: "Scan saved"
        }
    }

    private func preparePreview() async {
        guard session.phase == .ready, !session.pages.isEmpty else { return }
        let pages = session.pages
        let direction = stitchDirection
        let overlap = stitchOverlap
        let languages = settingsStore.general.recognitionLanguage
        isPreparing = true
        saveError = nil
        defer { if !Task.isCancelled { isPreparing = false } }
        do {
            if mode == .stitch, pages.count == 2 {
                try await Task.sleep(for: .milliseconds(200))
                let worker = Task.detached(priority: .userInitiated) {
                    try ImageStitcher.stitch(pages[0], pages[1], direction: direction, overlap: overlap)
                }
                let preview = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                preparedPreview = preview
            } else {
                preparedPreview = pages.last
            }
            if profile.outputFormat == .automatic, !manualOutput, let page = pages.first {
                if profile.source != .automatic {
                    detectedFormat = profile.source == .photo ? .jpeg : .pdf
                } else {
                    let worker = Task.detached(priority: .userInitiated) {
                        try ImageProcessor.classify(page, languages: languages.isEmpty ? [] : [languages])
                    }
                    let kind = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                    try Task.checkCancellation()
                    detectedFormat = kind == .document ? .pdf : .jpeg
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if profile.outputFormat == .automatic {
                detectedFormat = .pdf
                preparedPreview = pages.last
                saveError = "Automatic detection was unavailable. Choose PDF or JPEG below. Your image is intact. \(error.localizedDescription)"
            } else {
                preparedPreview = nil
                saveError = error.localizedDescription
            }
        }
    }

    private func rotateSelectedPage() {
        guard let page = selectedPage else { return }
        isEditing = true
        Task {
            defer { isEditing = false }
            do {
                let rotated = try await Task.detached(priority: .userInitiated) { try ScanPageEditing.rotateClockwise(page) }.value
                session.replacePage(id: page.id, with: rotated)
                editingRevision += 1
            } catch { saveError = error.localizedDescription }
        }
    }

    private func chooseDestination() {
        guard let format else { return }
        saveError = nil
        var settings = settingsStore.settings(for: mode)
        settings.scanOptions = profile.scanOptions
        settings.outputFormat = format
        settings.stitchDirection = stitchDirection
        settings.stitchOverlap = stitchOverlap
        let general = settingsStore.general
        let saveDate = Date()
        let panel = NSSavePanel()
        panel.title = "Save \(mode.displayName)"
        panel.message = settings.useDateSubfolder
            ? "Save inside a \(ScanFilename.dateSubfolder(date: saveDate)) subfolder of the selected folder."
            : "Choose a new file name. Existing files are preserved."
        panel.allowedContentTypes = [contentType(format)]
        panel.directoryURL = settings.saveDirectory
        let filename = ScanFilename.suggested(date: saveDate, prefix: settings.filenamePrefix)
        panel.nameFieldStringValue = (filename as NSString).deletingPathExtension + "." + format.fileExtension
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        showingSavePanel = true
        panel.begin { response in
            showingSavePanel = false
            guard response == .OK, let url = panel.url else { return }
            let plan = DocumentSavePlan(selectedURL: url, settings: settings, date: saveDate)
            do {
                try plan.prepareDirectory()
                pendingSaveProfile = settings
                pendingGeneral = general
                let exporter = ScanOutputExporter(mode: mode, profile: settings, general: general, format: format)
                Task { await session.export(to: plan.url, exporter: exporter) }
            } catch {
                saveError = "The save folder could not be prepared. \(error.localizedDescription) Your scans are still available."
            }
        }
    }

    private func contentType(_ format: ScanOutputFormat) -> UTType {
        switch format {
        case .automatic, .pdf: .pdf
        case .jpeg: .jpeg
        case .png: .png
        case .tiff: .tiff
        }
    }
}

private struct ScanThumbnail: View {
    let page: ScannedPage?
    var body: some View {
        Group {
            if let page, let image = NSImage(data: page.imageData) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
        }
        .frame(width: 155, height: 215)
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Scan preview")
    }
}
