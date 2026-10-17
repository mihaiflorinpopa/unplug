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
                brightnessControl(display)
                Toggle("Turn Off When a Monitor Connects", isOn: $model.builtinOffWithExternal)
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
                    brightnessControl(display)
                    if model.unreachable.contains(display.uuid) {
                        Button("Forget \(display.name)") { model.forget(display) }
                    }
                }
            }
        }
    }

    /// A slider in the window. Menus can't hold sliders, so the menu offers a
    /// submenu of levels instead. Hidden for displays without brightness control.
    @ViewBuilder
    private func brightnessControl(_ display: Display) -> some View {
        if display.isConnected, let level = model.brightness[display.uuid] {
            let percent = Int((level * 100).rounded())
            if inMenu {
                Menu("Brightness: \(percent)%") {
                    ForEach(Array(stride(from: 100, through: 0, by: -10)), id: \.self) { step in
                        Button("\(step)%") { model.setBrightness(display, Double(step) / 100) }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "sun.min")
                    Slider(
                        value: Binding(
                            get: { model.brightness[display.uuid] ?? level },
                            set: { model.setBrightness(display, $0) }),
                        in: 0...1
                    )
                    Text("\(percent)%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .accessibilityLabel("\(display.name) brightness")
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
    let showAbout: () -> Void
    let showHelp: () -> Void
    let showShortcuts: () -> Void

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
            Toggle("Keyboard Shortcuts (\(model.shortcutsSummary))", isOn: $model.shortcutsEnabled)
            Button("Change Keyboard Shortcuts…") { showShortcuts() }
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
            Toggle("Keep Displays Off After Restart", isOn: $model.keepOffAfterRestart)
            Divider()
            Toggle("Show in Dock", isOn: $model.showInDock)
            if updater.isAvailable {
                Divider()
                Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecks)
            }
        }
        Divider()
        Button("About Unplug") { showAbout() }
        Button("Unplug Help") { showHelp() }
        if updater.isAvailable {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheck)
        }
        Button("Quit Unplug") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
