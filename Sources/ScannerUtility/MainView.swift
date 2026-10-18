import AppKit
import ScannerCore
import SwiftUI

struct MainView: View {
    @ObservedObject var session: DocumentSession
    @ObservedObject var discovery: ScannerDiscovery
    @ObservedObject var settingsStore: DocumentSettingsStore
    @Binding var showingDocument: Bool
    @Binding var showingAdvanced: Bool
    @State private var showingInstructions = false
    @State private var activeMode = ScanWorkflowMode.document
    @State private var activeProfile = DocumentSettings()
    @State private var pendingAdvanced: DocumentSettings?
    @State private var startError: String?

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
                Text("Real scanner · \(settingsSummary). Document starts a physical scan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if discovery.debugModeEnabled {
                Label("Debug Mode · Mock Scanner is available for testing.", systemImage: "ladybug")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let startError {
                Label(startError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                ForEach(ScanWorkflowMode.allCases) { mode in
                    Button {
                        if mode == .advanced {
                            showingAdvanced = true
                        } else {
                            startScan(mode)
                        }
                    } label: {
                        VStack(spacing: 13) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 27, weight: .regular))
                                .frame(height: 34)
                            Text(mode.buttonTitle)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 107)
                        .foregroundStyle(discovery.hasAvailableScanner ? Color.accentColor : Color.secondary.opacity(0.65))
                        .background(Color.accentColor.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(discovery.isRefreshing || !discovery.hasAvailableScanner)
                    .help("Start \(mode.displayName)")
                    .accessibilityLabel(mode.buttonTitle)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a scan mode")
                        .font(.system(size: 12, weight: .medium))
                    Text("Document collects pages into one PDF. Photo saves an image; Stitch joins two overlapping scans.")
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
            DocumentView(session: session, settingsStore: settingsStore, mode: activeMode, profile: activeProfile) { showingDocument = false }
        }
        .sheet(isPresented: $showingAdvanced, onDismiss: {
            if let profile = pendingAdvanced {
                pendingAdvanced = nil
                startScan(.advanced, profile: profile)
            }
        }) {
            AdvancedScanView(profile: settingsStore.settings(for: .advanced), scannerName: discovery.selectedScannerName) { profile in
                pendingAdvanced = profile
                showingAdvanced = false
            } onCancel: {
                showingAdvanced = false
            }
        }
        .sheet(isPresented: $showingInstructions) {
            InstructionsView()
        }
    }

    private var settingsSummary: String {
        let options = settingsStore.settings.scanOptions
        return "\(options.paperSize.displayName) · \(options.colorMode.displayName) · \(options.resolution.displayName)"
    }

    private func startScan(_ mode: ScanWorkflowMode, profile override: DocumentSettings? = nil) {
        var profile = override ?? settingsStore.settings(for: mode)
        // Auto classifies one acquisition made with this profile's scan area and
        // resolution. There is no extra preview scan or hidden option override.
        profile.processing.blackAndWhite = profile.processing.blackAndWhite || profile.scanOptions.colorMode == .blackAndWhite
        do {
            try profile.scanOptions.validate()
            guard let backend = discovery.backend(options: profile.scanOptions) else { return }
            let language = settingsStore.general.recognitionLanguage
            let configured = ProcessingScannerBackend(backend: backend, processor: ImageProcessor(
                options: profile.processing, recognitionLanguages: language.isEmpty ? [] : [language]
            ))
            guard session.selectBackend(configured) else { return }
            startError = nil
            activeMode = mode
            activeProfile = profile
            showingDocument = true
            session.start()
        } catch {
            startError = error.localizedDescription
        }
    }
}

struct InstructionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Scanning with Scanner Utility")
                .font(.title2.bold())
            Text("Auto detects a document or photo locally after one scan. Document collects pages until Exit saves a combined PDF. Photo saves JPEG, PNG, or TIFF. Custom uses your own settings. Stitch scans two overlapping halves and joins them. Advanced lets you adjust native SANE settings before scanning.")
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
