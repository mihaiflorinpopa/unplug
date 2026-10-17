import AppKit
import SwiftUI
import UnplugCore

/// The display controls, shared by the menu bar menu and the window.
struct DisplaySections: View {
    @ObservedObject var model: DisplaysModel
    var inMenu = false

    private var builtin: [Display] { model.displays.filter(\.isBuiltin) }
    private var external: [Display] { model.displays.filter { !$0.isBuiltin } }

    var body: some View {
        // The built-in display and the keyboard backlight it controls, together.
        ForEach(builtin) { display in
            Section(display.name) {
                Toggle("Screen", isOn: connected(display))
                if model.keyboardBacklightAvailable {
                    Toggle("Keyboard Backlight", isOn: $model.keyboardLightOn)
                    Toggle("Turn Off Keyboard Backlight with Screen", isOn: $model.keyboardBacklightFollowsBuiltin)
                }
            }
        }

        if !external.isEmpty {
            if inMenu && !builtin.isEmpty { Divider() }
            Section("External Displays") {
                ForEach(external) { display in
                    Toggle(display.name, isOn: connected(display))
                    if model.unreachable.contains(display.uuid) {
                        Button("Forget \(display.name)") { model.forget(display) }
                    }
                }
            }
        }
    }

    private func connected(_ display: Display) -> Binding<Bool> {
        Binding(
            get: { display.isConnected },
            set: { model.setConnected(display, $0) }
        )
    }
}

struct MenuContent: View {
    @ObservedObject var model: DisplaysModel
    @ObservedObject var updater: Updater

    var body: some View {
        DisplaySections(model: model, inMenu: true)

        if let error = model.lastError {
            Divider()
            Text(error)
        }

        Divider()
        if model.displays.contains(where: { !$0.isConnected }) {
            Button("Reconnect All Displays") { model.connectAll() }
        }
        Menu("Options") {
            Toggle("Reconnect Displays on Quit", isOn: $model.reconnectOnQuit)
            Toggle("Keyboard Shortcuts (⌃⌥⌘U, ⌃⌥⌘B)", isOn: $model.shortcutsEnabled)
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
            Divider()
            Toggle("Show in Dock", isOn: $model.showInDock)
            if updater.isAvailable {
                Divider()
                Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecks)
            }
        }
        Divider()
        Text("Unplug \(UnplugVersion.current)")
        if updater.isAvailable {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheck)
        }
        Button("Quit Unplug") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
