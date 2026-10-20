import SwiftUI
import UnplugCore

/// The Settings window (⌘,), a SwiftUI `Settings` scene with one pane per
/// group. It opens on the pane used last, as Apple's guidelines suggest.
struct SettingsView: View {
    var model: DisplaysModel
    var updater: Updater
    @AppStorage("settingsPane") private var pane = Pane.displays

    enum Pane: String {
        case displays, general, shortcuts
    }

    // A grouped Form has no height of its own, so each pane is fixed to its
    // content's height and the window fits the pane, as Apple's guidelines ask.
    // shortcut: a Mac with many monitors could make the Displays pane taller
    // than a small screen; cap it and let it scroll if that ever happens.
    var body: some View {
        TabView(selection: $pane) {
            DisplaysForm(model: model)
                .fixedSize(horizontal: false, vertical: true)
                .tabItem { Label("Displays", systemImage: "display.2") }
                .tag(Pane.displays)
            GeneralSettings(model: model, updater: updater)
                .fixedSize(horizontal: false, vertical: true)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Pane.general)
            Form {
                ShortcutsSettings(model: model)
                ErrorSection(model: model)
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
            .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            .tag(Pane.shortcuts)
        }
        .frame(width: 460)
    }
}

struct GeneralSettings: View {
    @Bindable var model: DisplaysModel
    @Bindable var updater: Updater

    var body: some View {
        Form {
            Section {
                OptionToggle(option: .reconnectOnQuit, isOn: $model.reconnectOnQuit)
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
            ErrorSection(model: model)
        }
        .formStyle(.grouped)
    }
}
