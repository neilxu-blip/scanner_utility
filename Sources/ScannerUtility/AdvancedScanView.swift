import ScannerCore
import SwiftUI

struct AdvancedScanView: View {
    @State var profile: DocumentSettings
    let scannerName: String
    let onScan: (DocumentSettings) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Advanced Scan", systemImage: "slider.horizontal.3")
                .font(.title2.bold())
            Text("Native controls for \(scannerName). These replace the Windows ScanGear dialog; no scan starts until you choose Scan.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                Picker("Color mode", selection: $profile.scanOptions.colorMode) {
                    ForEach(ScanColorMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Paper size", selection: $profile.scanOptions.paperSize) {
                    ForEach(ScanPaperSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if profile.scanOptions.paperSize == .custom {
                    TextField("Width (mm)", value: $profile.scanOptions.customWidthMillimeters, format: .number)
                    TextField("Height (mm)", value: $profile.scanOptions.customHeightMillimeters, format: .number)
                }
                Picker("Resolution", selection: $profile.scanOptions.resolution) {
                    ForEach(ScanResolution.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Brightness") { Slider(value: $profile.processing.brightness, in: -1...1) }
                LabeledContent("Contrast") { Slider(value: $profile.processing.contrast, in: -1...1) }
                LabeledContent("Gamma") { Slider(value: $profile.processing.gamma, in: 0.1...3) }
                Toggle("Automatically crop the detected item", isOn: $profile.processing.autoCrop)
                Toggle("Sharpen outline", isOn: $profile.processing.sharpen)
            }
            Text("Large scans can exceed memory limits. Adjustments are applied locally after acquisition. Other output and review options use the Advanced Scan profile in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Reset adjustments") {
                    profile.processing.brightness = 0
                    profile.processing.contrast = 0
                    profile.processing.gamma = 1
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Scan") { onScan(profile) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
    }
}
