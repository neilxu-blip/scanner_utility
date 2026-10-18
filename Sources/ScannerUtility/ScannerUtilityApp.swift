import AppKit
import ScannerCore
import SwiftUI

@main
struct ScannerUtilityApp: App {
    @NSApplicationDelegateAdaptor(ScannerAppDelegate.self) private var appDelegate
    @StateObject private var session = DocumentSession(backend: MockScannerBackend(), exporter: PreferredPDFExporter())
    @StateObject private var discovery = ScannerDiscovery()
    @StateObject private var settingsStore = DocumentSettingsStore()
    @State private var showingDocument = false
    @State private var showingAdvanced = false

    var body: some Scene {
        Window("Scanner Utility", id: "main") {
            MainView(session: session, discovery: discovery, settingsStore: settingsStore, showingDocument: $showingDocument, showingAdvanced: $showingAdvanced)
                .onAppear { appDelegate.session = session }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Toggle("Debug Mode", isOn: Binding(
                    get: { discovery.debugModeEnabled },
                    set: { discovery.setDebugModeEnabled($0) }
                ))
                .disabled(showingDocument || showingAdvanced || discovery.isRefreshing)
            }
        }

        Settings {
            SettingsView(store: settingsStore, discovery: discovery, selectionLocked: showingDocument || showingAdvanced)
        }
    }
}

@MainActor
final class ScannerAppDelegate: NSObject, NSApplicationDelegate {
    weak var session: DocumentSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session, session.phase == .scanning || session.phase == .exporting ||
                (session.phase == .ready && !session.pages.isEmpty) else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Finish your document before quitting"
        alert.informativeText = "Your scanned pages are still in this session. Use Exit in the document window to save them together as a PDF."
        alert.addButton(withTitle: "Return to Document")
        alert.runModal()
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
