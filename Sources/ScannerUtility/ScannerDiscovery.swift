import Combine
import Foundation
import ScannerCore

@MainActor
final class ScannerDiscovery: ObservableObject {
    @Published private(set) var devices: [SANEDevice] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var message: String?
    @Published private(set) var debugModeEnabled = false
    @Published var selectedScannerID: String?
    private(set) var client: ScanimageClient?
    private let clientProvider: () -> ScanimageClient?

    init(clientProvider: @escaping () -> ScanimageClient? = {
        ScanimageClient.findExecutable().map { ScanimageClient(executable: $0) }
    }) {
        self.clientProvider = clientProvider
    }

    var selectedDevice: SANEDevice? {
        devices.first { $0.id == selectedScannerID }
    }

    var isMockSelected: Bool {
        debugModeEnabled && selectedScannerID == "mock"
    }

    var hasAvailableScanner: Bool {
        selectedDevice != nil || isMockSelected
    }

    var selectedScannerName: String {
        selectedDevice?.name ?? (isMockSelected ? "Mock Scanner" : "No scanner connected")
    }

    var selectedBackend: (any ScannerBackend)? {
        guard !isRefreshing else { return nil }
        if let device = selectedDevice, let client {
            return ScanimageScannerBackend(client: client, device: device)
        }
        return isMockSelected ? MockScannerBackend() : nil
    }

    func setDebugModeEnabled(_ enabled: Bool) {
        debugModeEnabled = enabled
        reconcileSelection()
    }

    private func reconcileSelection() {
        if selectedDevice != nil { return }
        selectedScannerID = devices.first?.id ?? (debugModeEnabled ? "mock" : nil)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        message = nil
        defer {
            reconcileSelection()
            isRefreshing = false
        }
        guard let client = clientProvider() else {
            devices = []
            client = nil
            message = "SANE is not installed. Install SANE to use a USB scanner."
            return
        }
        self.client = client
        do {
            devices = try await client.devices()
            if devices.isEmpty {
                message = "No SANE scanners found. Check the USB connection and click Refresh."
            }
        } catch is CancellationError {
            return
        } catch {
            devices = []
            message = error.localizedDescription
        }
    }
}
