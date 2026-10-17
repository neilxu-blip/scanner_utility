import AppKit
import ScannerCore
import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {
    @ObservedObject var session: DocumentSession
    var onClose: () -> Void
    @State private var showingSavePanel = false

    private var scanning: Bool { session.phase == .scanning }
    private var warmingUp: Bool { scanning && session.scanStatus == .warmingUp }
    private var acquisitionProgress: Double? {
        if case .scanning(let value) = session.scanStatus { return value }
        return nil
    }
    private var pageCountText: String {
        session.pages.count == 1 ? "1 page in this document" : "\(session.pages.count) pages in this document"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: scanning ? "scanner" : "doc.text")
                    .font(.system(size: 25))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if scanning {
                VStack(alignment: .leading, spacing: 10) {
                    if warmingUp {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Warming up scanner")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Getting the scanner ready for page \(session.pages.count + 1).")
                                Text("Scanning will begin when preparation is complete.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if let value = acquisitionProgress {
                        HStack {
                            Text("Scanning page \(session.pages.count + 1)…")
                            Spacer()
                            Text(value, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: value, total: 1)
                            .progressViewStyle(.linear)
                            .accessibilityLabel("Scanning progress")
                            .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
                        Text(value >= 1 ? "Finishing the scanned page…" : "Please wait until the current page is complete.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView("Scanning page \(session.pages.count + 1)…")
                            .controlSize(.small)
                        Text("The scanner is working but cannot report a progress percentage.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if session.phase == .exporting {
                ProgressView("Combining \(session.pages.count) pages into one PDF…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if session.phase == .ready {
                HStack(alignment: .top, spacing: 18) {
                    PageThumbnail(page: session.pages.last)
                    VStack(alignment: .leading, spacing: 9) {
                        Label(pageCountText, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.green)
                        Text("To continue scanning, place the next document and click Scan.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Click Exit to finish and save all pages as one PDF.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("The scan did not finish. You can try again.")
                    .foregroundStyle(.secondary)
            }

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(error)")
            }

            Divider()

            HStack {
                Text(session.scannerDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if scanning {
                    Button("Cancel") {
                        session.cancelScan()
                        if session.pages.isEmpty { onClose() }
                    }
                    .keyboardShortcut(.cancelAction)
                } else if session.phase == .ready {
                    Button("Scan") { session.scanNext() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(showingSavePanel)
                    Button("Exit") { choosePDFDestination() }
                        .disabled(showingSavePanel)
                } else if session.phase == .idle {
                    Button("Close") { onClose() }
                    Button("Try Again") { session.start() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 500)
        .interactiveDismissDisabled()
        .onChange(of: session.phase) { _, phase in
            if phase == .saved { onClose() }
        }
    }

    private var title: String {
        switch session.phase {
        case .scanning:
            warmingUp ? "Warming up…" : (acquisitionProgress == 1 ? "Finishing scan…" : "Scanning…")
        case .exporting: "Saving document…"
        case .ready: session.errorMessage == nil ? "Scan complete" : "Document session"
        case .idle: "Scan stopped"
        case .saved: "Document saved"
        }
    }

    private var subtitle: String {
        scanning ? "Keep the document cover closed." : "Document · Combined PDF"
    }

    private func choosePDFDestination() {
        let panel = NSSavePanel()
        panel.title = "Save scanned document"
        panel.message = "Save all \(session.pages.count) scanned pages as one PDF. Choose a new filename."
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = ScanFilename.suggested()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        showingSavePanel = true
        panel.begin { response in
            showingSavePanel = false
            guard response == .OK, let url = panel.url else { return }
            Task { await session.export(to: url) }
        }
    }
}

private struct PageThumbnail: View {
    let page: ScannedPage?

    var body: some View {
        Group {
            if let page, let image = NSImage(data: page.imageData) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 76, height: 106)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.12)))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
        .accessibilityLabel("Preview of the last scanned page")
    }
}
