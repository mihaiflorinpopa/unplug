import AppKit
import SwiftUI
import UnplugCore

/// The window for people who prefer a regular app to a menu bar app. It shows
/// the same controls as the menu. Kept alive when closed so reopening is instant.
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    private let model: DisplaysModel
    private let updater: Updater
    private var window: NSWindow?

    init(model: DisplaysModel, updater: Updater) {
        self.model = model
        self.updater = updater
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: MainWindowView(model: model, updater: updater)))
        window.title = "Unplug"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 420, height: 560))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// Picks up changes made elsewhere (the CLI).
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
        model.refreshBrightness()
    }
}

struct MainWindowView: View {
    @ObservedObject var model: DisplaysModel
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            DisplaySections(model: model)

            if model.displays.contains(where: { !$0.isConnected }) {
                Section {
                    Button("Reconnect All Displays") { model.connectAll() }
                }
            }

            if let error = model.lastError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section("Options") {
                OptionToggle(option: .reconnectOnQuit, isOn: $model.reconnectOnQuit)
                ShortcutsSettings(model: model)
                OptionToggle(option: .launchAtLogin, isOn: $model.launchAtLogin)
                OptionToggle(option: .keepOffAfterRestart, isOn: $model.keepOffAfterRestart)
                OptionToggle(option: .showInMenuBar, isOn: $model.showInMenuBar)
                OptionToggle(option: .showInDock, isOn: $model.showInDock)
            }

            Section {
                if updater.isAvailable {
                    OptionToggle(option: .automaticUpdates, isOn: $updater.automaticallyChecks)
                }
                LabeledContent("Version \(UnplugVersion.current)") {
                    if updater.isAvailable {
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .disabled(!updater.canCheck)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 420)
    }
}

/// The display controls in the window, built-in screen first.
struct DisplaySections: View {
    @ObservedObject var model: DisplaysModel

    private var builtin: [Display] { model.displays.filter(\.isBuiltin) }
    private var external: [Display] { model.displays.filter { !$0.isBuiltin } }

    var body: some View {
        // The built-in display and the keyboard backlight it controls, together.
        ForEach(builtin) { display in
            Section(display.name) {
                Toggle("Screen", isOn: model.connected(display))
                brightnessSlider(display)
                OptionToggle(option: .builtinOffWithExternal, isOn: $model.builtinOffWithExternal)
                if model.keyboardBacklightAvailable {
                    OptionToggle(option: .keyboardBacklight, isOn: $model.keyboardLightOn)
                    OptionToggle(option: .keyboardBacklightFollowsBuiltin, isOn: $model.keyboardBacklightFollowsBuiltin)
                }
            }
        }

        if !external.isEmpty {
            Section("External Displays") {
                ForEach(external) { display in
                    Toggle(display.name, isOn: model.connected(display))
                    brightnessSlider(display)
                    if model.unreachable.contains(display.uuid) {
                        Button("Forget \(display.name)") { model.forget(display) }
                    }
                }
            }
        }
    }

    /// Hidden for displays without brightness control.
    @ViewBuilder
    private func brightnessSlider(_ display: Display) -> some View {
        if display.isConnected, let level = model.brightness[display.uuid] {
            HStack {
                Image(systemName: "sun.min")
                Slider(
                    value: Binding(
                        get: { model.brightness[display.uuid] ?? level },
                        set: { model.setBrightness(display, $0) }),
                    in: 0...1
                )
                Text("\(Int((level * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .accessibilityLabel("\(display.name) brightness")
        }
    }
}
