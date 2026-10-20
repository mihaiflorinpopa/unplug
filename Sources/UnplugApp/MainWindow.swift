import AppKit
import SwiftUI
import UnplugCore

/// The window for people who prefer a regular app to a menu bar app ("Show in
/// Dock"): the displays and their brightness. Options are in Settings. Kept
/// alive when closed so reopening is instant.
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    private let model: DisplaysModel
    private var window: NSWindow?

    init(model: DisplaysModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: DisplaysForm(model: model)))
        window.title = "Unplug"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 420, height: 480))
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

/// The displays, in the Dock window and in Settings > Displays.
struct DisplaysForm: View {
    var model: DisplaysModel

    var body: some View {
        Form {
            DisplaySections(model: model)
            if model.displays.contains(where: { !$0.isConnected }) {
                Section {
                    Button("Reconnect All Displays") { model.connectAll() }
                }
            }
            ErrorSection(model: model)
        }
        .formStyle(.grouped)
        // Picks up changes made elsewhere (the CLI, the brightness keys).
        .onAppear {
            model.refresh()
            model.refreshBrightness()
        }
    }
}

/// The last error, at the bottom of a form.
struct ErrorSection: View {
    var model: DisplaysModel

    var body: some View {
        if let error = model.lastError {
            Section {
                Text(error).foregroundStyle(.red)
            }
        }
    }
}

/// The display controls, built-in screen first.
struct DisplaySections: View {
    @Bindable var model: DisplaysModel

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

    /// Laid out like macOS's own Displays settings: a Brightness label, then the slider.
    @ViewBuilder
    private func brightnessSlider(_ display: Display) -> some View {
        if display.isConnected, model.brightness[display.uuid] != nil {
            LabeledContent("Brightness") {
                BrightnessSlider(model: model, display: display)
                    .frame(minWidth: 300)
            }
        }
    }
}

/// A display's brightness: the slider with a small sun at the low end and a
/// large sun at the high end, as the HIG suggests for sliders, then the level in
/// percent. Used in Settings and the Dock window. Shows nothing for a
/// display without brightness control.
struct BrightnessSlider: View {
    var model: DisplaysModel
    let display: Display

    var body: some View {
        if let level = model.brightness[display.uuid] {
            HStack {
                Slider(
                    value: Binding(
                        get: { model.brightness[display.uuid] ?? level },
                        set: { model.setBrightness(display, $0) }),
                    in: 0...1
                ) {
                    // Hidden on screen, read by VoiceOver.
                    Text("\(display.name) brightness")
                } minimumValueLabel: {
                    Image(systemName: "sun.min")
                } maximumValueLabel: {
                    Image(systemName: "sun.max")
                }
                .labelsHidden()
                Text("\(Int((level * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}
