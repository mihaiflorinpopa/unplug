import AppKit
import SwiftUI
import UnplugCore

/// The menu bar menu: only what's used often. Every option is in Settings.
struct MenuContent: View {
    @Bindable var model: DisplaysModel
    var updater: Updater
    let showAbout: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Section("Displays") {
            ForEach(model.displays) { display in
                Toggle(display.name, isOn: model.connected(display))
                brightnessMenu(display)
                if model.unreachable.contains(display.uuid) {
                    Button("Forget \(display.name)") { model.forget(display) }
                }
            }
        }

        if model.keyboardBacklightAvailable {
            Divider()
            Toggle(Option.keyboardBacklight.title, isOn: $model.keyboardLightOn)
        }

        if let error = model.lastError {
            Divider()
            Text(error)
        }

        if model.displays.contains(where: { !$0.isConnected }) {
            Divider()
            Button("Reconnect All Displays") { model.connectAll() }
        }

        Divider()
        if updater.updateAvailable {
            Button("Update Available…") {
                NSApp.activate()
                updater.checkForUpdates()
            }
        }
        Button("Settings…") {
            // A menu bar app isn't active, so bring it forward with its Settings window.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("About Unplug") { showAbout() }
        // Opens the Help Book that Info.plist names.
        Button("Unplug Help") { NSApp.showHelp(nil) }
        Button("Quit Unplug") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Menus can't hold sliders, so the menu offers a submenu of levels.
    /// Hidden for displays without brightness control.
    @ViewBuilder
    private func brightnessMenu(_ display: Display) -> some View {
        if display.isConnected, let level = model.brightness[display.uuid] {
            Menu("Brightness: \(Int((level * 100).rounded()))%") {
                ForEach(Array(stride(from: 100, through: 0, by: -10)), id: \.self) { step in
                    Button("\(step)%") { model.setBrightness(display, Double(step) / 100) }
                }
            }
        }
    }
}
