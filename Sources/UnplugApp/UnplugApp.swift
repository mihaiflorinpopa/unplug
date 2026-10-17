import AppKit
import ServiceManagement
import SwiftUI
import UnplugCore

@main
struct UnplugApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = DisplaysModel()

    var body: some Scene {
        MenuBarExtra("Unplug", systemImage: "display.2") {
            MenuContent(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        if UserDefaults.standard.object(forKey: DisplaysModel.reconnectOnQuitKey) as? Bool ?? true {
            DisplayManager().connectAll()
        }
    }
}

@MainActor
final class DisplaysModel: ObservableObject {
    static let reconnectOnQuitKey = "reconnectOnQuit"

    @Published private(set) var displays: [Display] = []
    @Published var lastError: String?
    @AppStorage(reconnectOnQuitKey) var reconnectOnQuit = true

    private let manager = DisplayManager()
    private var monitor: DisplayMonitor?

    init() {
        refresh()
        monitor = DisplayMonitor { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        displays = manager.displays()
    }

    func setConnected(_ display: Display, _ connected: Bool) {
        do {
            if connected {
                try manager.connect(display)
            } else {
                try manager.disconnect(display)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func connectAll() {
        let failures = manager.connectAll()
        lastError = failures.first.map { "\($0.0.name): \($0.1.localizedDescription)" }
        refresh()
    }

    var keyboardBacklightFollowsBuiltin: Bool {
        get { UnplugSettings.keyboardBacklightFollowsBuiltin }
        set {
            UnplugSettings.keyboardBacklightFollowsBuiltin = newValue
            objectWillChange.send()
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                lastError = error.localizedDescription
            }
            objectWillChange.send()
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: DisplaysModel

    var body: some View {
        ForEach(model.displays) { display in
            Toggle(label(for: display), isOn: Binding(
                get: { display.isConnected },
                set: { model.setConnected(display, $0) }
            ))
            if display.isBuiltin {
                // Sits right under the built-in display it applies to.
                Toggle("    Keyboard Light Off Too", isOn: $model.keyboardBacklightFollowsBuiltin)
            }
        }

        if model.displays.contains(where: { !$0.isConnected }) {
            Button("Reconnect All") { model.connectAll() }
        }

        if let error = model.lastError {
            Divider()
            Text(error)
        }

        Divider()
        Toggle("Reconnect Displays on Quit", isOn: $model.reconnectOnQuit)
        Toggle("Launch at Login", isOn: $model.launchAtLogin)
        Divider()
        Button("Quit Unplug") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func label(for display: Display) -> String {
        display.isBuiltin ? "\(display.name) (Built-in)" : display.name
    }
}
