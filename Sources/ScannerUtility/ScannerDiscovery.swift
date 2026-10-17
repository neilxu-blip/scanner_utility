import Combine
import Foundation
import ScannerCore

@MainActor
final class ScannerDiscovery: ObservableObject {
    @Published private(set) var devices: [SANEDevice] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var message: String?
    private(set) var client: ScanimageClient?

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        message = nil
        defer { isRefreshing = false }
        guard let executable = ScanimageClient.findExecutable() else {
            devices = []
            client = nil
            message = "SANE is not installed. Mock Scanner is available for testing."
            return
        }
        let client = ScanimageClient(executable: executable)
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
