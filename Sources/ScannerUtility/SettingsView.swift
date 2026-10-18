import AppKit
import ScannerCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: DocumentSettingsStore
    @ObservedObject var discovery: ScannerDiscovery
    var selectionLocked = false
    @State private var draft = DocumentSettings()
    @State private var drafts: [ScanWorkflowMode: DocumentSettings] = [:]
    @State private var generalDraft = GeneralSettings()
    @State private var selection = ScanWorkflowMode.document
    @State private var section = SettingsSection.scanning
    @State private var showingImageProcessing = false
    @State private var windowNumber: Int?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                pageHeader
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if section == .scanning {
                            scanOptions
                            saveSettings
                            applicationSettings
                        } else {
                            generalSettings
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Start each newly selected page at its heading and first controls.
                .id(destination.wrappedValue)
                Divider()
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 980, height: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsWindowReader { window in
            windowNumber = window.windowNumber
            window.title = windowTitle
        })
        .onAppear { reloadDrafts() }
        .onChange(of: selection) { oldMode, newMode in
            drafts[oldMode] = draft
            draft = drafts[newMode] ?? store.settings(for: newMode)
            showingImageProcessing = false
            updateWindowTitle()
        }
        .onChange(of: section) { _, _ in updateWindowTitle() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.windowNumber == windowNumber else { return }
            // SwiftUI can reuse Settings windows without another onAppear.
            reloadDrafts()
        }
    }

    private var destination: Binding<SettingsDestination?> {
        Binding(
            get: { section == .general ? .general : .scan(selection) },
            set: { destination in
                switch destination {
                case .general:
                    section = .general
                case .scan(let mode):
                    selection = mode
                    section = .scanning
                case nil:
                    break // Keep one page selected when clicking empty sidebar space.
                }
            }
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 18)

            List(selection: destination) {
                Label("General", systemImage: "gearshape")
                    .padding(.vertical, 7)
                    .tag(SettingsDestination.general)

                Section("Scanning") {
                    ForEach(ScanWorkflowMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.symbol)
                            .padding(.vertical, 7)
                            .tag(SettingsDestination.scan(mode))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Settings navigation")

            Link(destination: instructionsURL) {
                Label("Instructions", systemImage: "questionmark.circle")
            }
            .padding(20)
        }
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: section == .general ? "gearshape" : selection.symbol)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(section == .general ? "General" : selection.displayName)
                    .font(.title2.bold())
                Text(section == .general
                     ? "Choose your scanner and shared preferences for all scan modes."
                     : modeDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Defaults") {
                if section == .general { generalDraft = GeneralSettings() }
                else { draft = store.defaultSettings(for: selection) }
            }
            .help(section == .general ? "Restore defaults for General settings" : "Restore defaults for \(selection.displayName)")
            Spacer()
            Button("Cancel") { closeWindow() }
                .keyboardShortcut(.cancelAction)
            Button("OK") {
                drafts[selection] = draft
                for (mode, profile) in drafts { store.save(profile, for: mode) }
                store.saveGeneral(generalDraft)
                closeWindow()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var scanOptions: some View {
        GroupBox("Scan Options") {
            VStack(alignment: .leading, spacing: 13) {
                settingsRow("Select source") {
                    Picker("Select source", selection: $draft.source) {
                        ForEach(ScanSource.allCases, id: \.self) { source in Text(source.displayName).tag(source) }
                    }
                    .labelsHidden()
                    .onChange(of: draft.source) { _, source in
                        if source == .magazine { draft.processing.reduceMoire = true }
                    }
                }
                settingsRow("Color mode") {
                    Picker("Color mode", selection: $draft.scanOptions.colorMode) {
                        ForEach(ScanColorMode.allCases, id: \.self) { mode in Text(mode.displayName).tag(mode) }
                    }.labelsHidden()
                }
                settingsRow("Paper size") {
                    Picker("Paper size", selection: $draft.scanOptions.paperSize) {
                        ForEach(ScanPaperSize.allCases, id: \.self) { size in Text(size.displayName).tag(size) }
                    }.labelsHidden()
                }
                if draft.scanOptions.paperSize == .custom {
                    settingsRow("Custom size (mm)") {
                        HStack {
                            TextField("Width", value: $draft.scanOptions.customWidthMillimeters, format: .number.precision(.fractionLength(0...1)))
                                .accessibilityLabel("Custom width in millimeters")
                            Text("×")
                            TextField("Height", value: $draft.scanOptions.customHeightMillimeters, format: .number.precision(.fractionLength(0...1)))
                                .accessibilityLabel("Custom height in millimeters")
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                    Text("Custom acquisition size: width 10–216 mm, height 10–297 mm. Your scanner may support a smaller area.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                settingsRow("Resolution") {
                    Picker("Resolution", selection: $draft.scanOptions.resolution) {
                        ForEach(ScanResolution.allCases, id: \.self) { resolution in Text(resolution.displayName).tag(resolution) }
                    }.labelsHidden()
                }
                if selection == .stitch { stitchSettings }
                DisclosureGroup("Image Processing Settings", isExpanded: $showingImageProcessing) {
                    imageProcessingSettings.padding(.top, 8)
                }
                Text("Scan options apply to the next session. Auto detects item type after one scan using this area and resolution. Selecting Magazine enables moiré reduction, which you can adjust below. Higher resolutions require more memory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private var imageProcessingSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Crop to detected item", isOn: $draft.processing.autoCrop)
            Toggle("Apply automatic image enhancement", isOn: $draft.processing.autoEnhance)
            Toggle("Sharpen outlines", isOn: $draft.processing.sharpen)
            Toggle("Reduce show-through", isOn: $draft.processing.reduceShowThrough)
            Toggle("Reduce moiré", isOn: $draft.processing.reduceMoire)
            Toggle("Reduce gutter shadow", isOn: $draft.processing.reduceGutterShadow)
            Toggle("Correct slanted documents", isOn: $draft.processing.deskew)
            Toggle("Rotate text to an upright orientation", isOn: $draft.processing.autoRotate)
            Toggle("Convert processed image to black and white", isOn: $draft.processing.blackAndWhite)
            if selection == .advanced {
                Divider().padding(.vertical, 4)
                adjustmentRow("Brightness", value: $draft.processing.brightness, range: -1...1)
                adjustmentRow("Contrast", value: $draft.processing.contrast, range: -1...1)
                adjustmentRow("Gamma", value: $draft.processing.gamma, range: 0.1...3)
            }
            Text("Corrections use macOS image processing after acquisition. Automatic crop, deskew, and rotation depend on detecting the item and text.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var stitchSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsRow("Stitch direction") {
                Picker("Stitch direction", selection: $draft.stitchDirection) {
                    Text("Left to right").tag(StitchDirection.horizontal)
                    Text("Top to bottom").tag(StitchDirection.vertical)
                }.labelsHidden()
            }
            settingsRow("Overlap") {
                HStack {
                    Slider(value: $draft.stitchOverlap, in: 0...0.5, step: 0.01)
                    Text(draft.stitchOverlap, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 45)
                }
            }
            Text("Scan the first part, then move the item in the chosen direction. Include the selected overlap in both scans. Two parts form one image.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var saveSettings: some View {
        GroupBox("Save Settings") {
            VStack(alignment: .leading, spacing: 13) {
                settingsRow("File name") {
                    TextField("Scanned Document", text: $draft.filenamePrefix)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("File name prefix")
                }
                Text("The date and time are added automatically. Image formats save one image; PDF collects pages into one file.")
                    .font(.caption).foregroundStyle(.secondary)
                settingsRow("Save in") {
                    folderRow(draft.saveDirectory) {
                        chooseFolder(title: "Choose a folder for scanned files", current: draft.saveDirectory) { draft.saveDirectory = $0 }
                    }
                }
                settingsRow("Data format") {
                    Picker("Data format", selection: $draft.outputFormat) {
                        ForEach(ScanOutputFormat.allCases, id: \.self) { format in Text(format.displayName).tag(format) }
                    }.labelsHidden()
                }
                if draft.outputFormat == .pdf || draft.outputFormat == .automatic {
                    settingsRow("PDF compression") {
                        Picker("PDF compression", selection: $draft.compression) {
                            Text("Standard (smaller files)").tag(PDFCompression.standard)
                            Text("High quality").tag(PDFCompression.highQuality)
                            Text("Lossless (large files)").tag(PDFCompression.lossless)
                        }.labelsHidden()
                    }
                    Text(compressionDescription).font(.caption).foregroundStyle(.secondary)
                    Toggle("Create a PDF that supports keyword search", isOn: $draft.searchablePDF)
                    Text("Text recognition uses the document language in General Settings. Recognition accuracy varies with the source.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if draft.outputFormat == .jpeg || draft.outputFormat == .automatic {
                    settingsRow("JPEG quality") {
                        HStack {
                            Slider(value: $draft.jpegQuality, in: 0.1...1, step: 0.05)
                            Text(draft.jpegQuality, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 45)
                        }
                    }
                }
                Toggle("Save to a subfolder with the current date", isOn: $draft.useDateSubfolder)
                Toggle("Check scan results and choose a destination before saving", isOn: $draft.checkScanResults)
                Text("PDF combines the session's pages. JPEG, PNG, and TIFF save one file per page. With result checking off, files are saved directly to the selected folder; existing files are never replaced.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private var applicationSettings: some View {
        GroupBox("Application Settings") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("After saving", selection: $draft.afterSave) {
                    ForEach(AfterSaveAction.allCases, id: \.self) { action in Text(action.displayName).tag(action) }
                }.pickerStyle(.radioGroup)
                if draft.afterSave == .openApplication {
                    settingsRow("Application") {
                        HStack {
                            Text(draft.applicationURL?.deletingPathExtension().lastPathComponent ?? "Choose an application")
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Choose…") { chooseApplication() }
                        }
                    }
                }
                if draft.afterSave == .copyToFolder {
                    settingsRow("Additional folder") {
                        folderRow(draft.secondaryDirectory) {
                            chooseFolder(title: "Choose an additional copy destination", current: draft.secondaryDirectory) { draft.secondaryDirectory = $0 }
                        }
                    }
                }
                Text(afterSaveDescription).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    @ViewBuilder
    private var generalSettings: some View {
        GroupBox("Scanner") {
            VStack(alignment: .leading, spacing: 18) {
                settingsRow("Product name") {
                    HStack {
                        Picker("Product name", selection: $discovery.selectedScannerID) {
                            if !discovery.hasAvailableScanner { Text("No scanner connected").tag(String?.none) }
                            ForEach(discovery.devices) { device in Text(device.name).tag(Optional(device.id)) }
                            if discovery.debugModeEnabled { Text("Mock Scanner").tag(Optional("mock")) }
                        }
                        .labelsHidden()
                        .disabled(selectionLocked || discovery.isRefreshing || !discovery.hasAvailableScanner)
                        Button("Refresh") { Task { await discovery.refresh() } }
                            .disabled(selectionLocked || discovery.isRefreshing)
                    }
                }
                if let message = discovery.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if selectionLocked {
                    Text("Finish the current scan session to change the scanner.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Product selection is shared with the main window and changes immediately. Mock Scanner appears only in View → Debug Mode.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }

        GroupBox("Text Recognition") {
            VStack(alignment: .leading, spacing: 13) {
                settingsRow("Document language") {
                    Picker("Document language", selection: $generalDraft.recognitionLanguage) {
                        Text("Automatic").tag("")
                        Text("English").tag("en-US")
                        Text("Chinese (Simplified)").tag("zh-Hans")
                        Text("Chinese (Traditional)").tag("zh-Hant")
                        Text("Japanese").tag("ja-JP")
                        Text("French").tag("fr-FR")
                        Text("German").tag("de-DE")
                        Text("Spanish").tag("es-ES")
                    }.labelsHidden()
                }
                Text("Used for searchable PDFs, text export, and text orientation detection.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }

        GroupBox("Outgoing Images") {
            VStack(alignment: .leading, spacing: 13) {
                settingsRow("Send image size") {
                    Picker("Send image size", selection: $generalDraft.sendImageSize) {
                        ForEach(SendImageSize.allCases, id: \.self) { size in Text(size.displayName).tag(size) }
                    }.labelsHidden()
                }
                Text("Limits the longest side of image copies sent to another application or attached to an email draft. Saved originals and PDFs keep their dimensions.")
                    .font(.caption).foregroundStyle(.secondary)
                settingsRow("Temporary folder") {
                    folderRow(generalDraft.temporaryDirectory) {
                        chooseFolder(title: "Choose a folder for temporary outgoing files", current: generalDraft.temporaryDirectory) { generalDraft.temporaryDirectory = $0 }
                    }
                }
                Text("Used for temporary image copies sent to another application or attached to email. Scan sessions stay in memory until saved; this folder does not provide crash recovery.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 140, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func folderRow(_ url: URL?, choose: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "folder").foregroundStyle(.tint)
            Text(url?.path ?? "Choose a folder")
                .lineLimit(1).truncationMode(.middle).help(url?.path ?? "")
            Spacer(minLength: 0)
            Button("Choose…", action: choose)
        }
    }

    private func adjustmentRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        settingsRow(title) {
            HStack {
                Slider(value: value, in: range, step: 0.05)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit().frame(width: 45)
            }
        }
    }

    private var compressionDescription: String {
        switch draft.compression {
        case .standard: "Smaller files with slight image quality loss; scanned pixel dimensions are preserved."
        case .highQuality: "Preserves more fine detail with larger files; scanned pixel dimensions are preserved."
        case .lossless: "Preserves the processed image pixels and creates much larger files."
        }
    }

    private var afterSaveDescription: String {
        switch draft.afterSave {
        case .composeEmail: "Opens a draft in the default email application. Review the recipients and attachments yourself; the app never sends email automatically."
        case .extractText: "Uses macOS text recognition and the language in General Settings to create a UTF-8 text file beside the saved scans."
        case .copyToFolder: "Creates an additional copy after saving. Existing destination files are never replaced."
        default: "Application actions run only after the scanned files have been saved successfully."
        }
    }

    private var modeDescription: String {
        switch selection {
        case .auto: "Automatically identifies text documents or photos and chooses PDF or JPEG when the data format is Automatic. Review detection results before saving."
        case .document: "Scan consecutive pages into one document, then choose Exit to save the complete batch."
        case .photo: "Scan photos with a separate high-resolution profile and your preferred image format."
        case .custom: "Keep your own acquisition, correction, and saving choices in a separate profile."
        case .stitch: "Combine two overlapping scans of an item larger than the scanner bed."
        case .advanced: "Native SANE acquisition and macOS image adjustments. Canon's Windows-only ScanGear driver is not used."
        }
    }

    private var instructionsURL: URL {
        let page = section == .general ? "su-209.html" : "Su-PAGE3.html"
        return URL(string: "https://ij.manual.canon/ij/webmanual/ScanUtility/W/LiDE%20120/1.1/EN/SU/\(page)")!
    }

    private var windowTitle: String { section == .general ? "Settings (General)" : "Settings (\(selection.displayName))" }

    private func updateWindowTitle() {
        if let windowNumber { NSApp.window(withWindowNumber: windowNumber)?.title = windowTitle }
    }

    private func reloadDrafts() {
        drafts = Dictionary(uniqueKeysWithValues: ScanWorkflowMode.allCases.map { ($0, store.settings(for: $0)) })
        draft = drafts[selection] ?? store.settings(for: selection)
        generalDraft = store.general
    }

    private func chooseFolder(title: String, current: URL?, completion: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK, let url = panel.url { completion(url) }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application to open saved scans"
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK, let url = panel.url { draft.applicationURL = url }
        }
    }

    private func closeWindow() {
        reloadDrafts()
        if let windowNumber { NSApp.window(withWindowNumber: windowNumber)?.performClose(nil) }
    }
}

private enum SettingsSection { case scanning, general }

private enum SettingsDestination: Hashable {
    case general
    case scan(ScanWorkflowMode)
}

private struct SettingsWindowReader: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> SettingsWindowObserver {
        let view = SettingsWindowObserver()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: SettingsWindowObserver, context: Context) { nsView.onWindow = onWindow }
}

private final class SettingsWindowObserver: NSView {
    var onWindow: (@MainActor (NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor [weak self, weak window] in
            guard let window else { return }
            self?.onWindow?(window)
        }
    }
}
