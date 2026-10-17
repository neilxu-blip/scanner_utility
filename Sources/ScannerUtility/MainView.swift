import AppKit
import ScannerCore
import SwiftUI

struct MainView: View {
    @ObservedObject var session: DocumentSession
    @ObservedObject var discovery: ScannerDiscovery
    @Binding var showingDocument: Bool
    @State private var showingInstructions = false

    private let modes: [ScanMode] = [
        .init(name: "Auto", symbol: "sparkles.rectangle.stack"),
        .init(name: "Document", symbol: "doc.text", available: true),
        .init(name: "Photo", symbol: "photo"),
        .init(name: "Custom", symbol: "slider.horizontal.3"),
        .init(name: "Stitch", symbol: "rectangle.on.rectangle"),
        .init(name: "Advanced", symbol: "scanner")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 13) {
                Image(systemName: "scanner.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 54, height: 54)
                    .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scanner Utility")
                        .font(.system(size: 23, weight: .semibold))
                    Text("Your documents, one page at a time.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Text("Product name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("Product name", selection: $discovery.selectedScannerID) {
                    if !discovery.hasAvailableScanner {
                        Text("No scanner connected").tag(nil as String?)
                    }
                    ForEach(discovery.devices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                    if discovery.debugModeEnabled {
                        Text("Mock Scanner").tag(Optional("mock"))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Product name")
                .disabled(discovery.isRefreshing || !discovery.hasAvailableScanner)
                Button {
                    Task { await discovery.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(discovery.isRefreshing)
            }

            if discovery.isRefreshing {
                ProgressView("Looking for scanners…")
                    .controlSize(.small)
            } else if let message = discovery.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if discovery.selectedDevice != nil {
                Text("Real scanner · A4 · Color · 300 dpi. Document starts a physical scan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if discovery.debugModeEnabled {
                Label("Debug Mode · Mock Scanner is available for testing.", systemImage: "ladybug")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(modes) { mode in
                    Button {
                        guard let backend = discovery.selectedBackend,
                              session.selectBackend(backend) else { return }
                        showingDocument = true
                        session.start()
                    } label: {
                        VStack(spacing: 13) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 27, weight: .regular))
                                .frame(height: 34)
                            Text(mode.name)
                                .font(.system(size: 12, weight: mode.available ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 107)
                        .foregroundStyle(mode.available ? Color.accentColor : Color.secondary.opacity(0.65))
                        .background(mode.available ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(mode.available ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!mode.available || discovery.isRefreshing || !discovery.hasAvailableScanner)
                    .help(mode.available ? "Scan pages into one PDF" : "This scan type is not available yet")
                    .accessibilityLabel(mode.available ? "Document" : "\(mode.name), not available yet")
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start with Document")
                        .font(.system(size: 12, weight: .medium))
                    Text("Scan each page, then choose Exit to save one combined PDF.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Instructions") { showingInstructions = true }
                Spacer()
                Label(discovery.selectedScannerName, systemImage: "circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                SettingsLink {
                    Text("Settings…")
                }
            }
        }
        .padding(28)
        .frame(width: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await discovery.refresh() }
        .sheet(isPresented: $showingDocument) {
            DocumentView(session: session) { showingDocument = false }
        }
        .sheet(isPresented: $showingInstructions) {
            InstructionsView()
        }
    }

}

private struct ScanMode: Identifiable {
    let name: String
    let symbol: String
    var available = false
    var id: String { name }
}

struct InstructionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Scan a document")
                .font(.title2.bold())
            Text("1. Choose Document to scan the first page.\n\n2. When it finishes, place your next page and choose Scan. Repeat for each page.\n\n3. Choose Exit, then select where to save the combined PDF.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Connect your scanner and click Refresh if needed. Document and each subsequent Scan start the selected scanner. For testing without hardware, enable View → Debug Mode and choose Mock Scanner. Pages stay in the session until you save; canceling a scan keeps earlier pages.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 440)
    }
}

struct SettingsView: View {
    @AppStorage(PDFPreferences.compressionKey) private var compression = PDFCompression.standard.rawValue

    var body: some View {
        Form {
            LabeledContent("Scanner", value: "Choose in the main window")
            LabeledContent("Output", value: "One PDF per document session")
            LabeledContent("Page size", value: "A4")
            LabeledContent("Real scan settings", value: "Color · 300 dpi · 8-bit per channel")
            Picker("PDF quality", selection: $compression) {
                Text("Standard (smaller files)").tag(PDFCompression.standard.rawValue)
                Text("High quality").tag(PDFCompression.highQuality.rawValue)
                Text("Lossless (large files)").tag(PDFCompression.lossless.rawValue)
            }
            Text(compressionDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Real scanners use the installed SANE scanimage utility. Click Refresh after connecting your USB scanner. Enable View → Debug Mode to make Mock Scanner available for testing without hardware.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)
    }

    private var compressionDescription: String {
        switch PDFCompression(rawValue: compression) ?? .standard {
        case .standard: "Smaller PDFs with slight image quality loss. Page resolution and color are preserved."
        case .highQuality: "Less compression for fine details, with larger PDF files. Page resolution and color are preserved."
        case .lossless: "Preserves the original image pixels and creates much larger PDFs."
        }
    }
}
