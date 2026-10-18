import SwiftUI

/// A toggle with a one-line description: shown under the title in the
/// window, and as a tooltip in the menu, where items stay one line.
struct OptionToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var inMenu = false

    var body: some View {
        if inMenu {
            Toggle(title, isOn: $isOn).help(detail)
        } else {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Descriptions shared by the window, the menu and Help.
enum OptionDetail {
    static let builtinOffWithExternal = "Turns the built-in screen off when you plug in a monitor. It always comes back when the last monitor is unplugged."
    static let keyboardBacklight = "Turns the keyboard backlight on or off."
    static let keyboardBacklightFollowsBuiltin = "The keyboard backlight goes off with the built-in screen and comes back with it."
    static let reconnectOnQuit = "Quitting Unplug turns every display back on."
    static let shortcuts = "Shortcuts that work in any app. Click one to change it."
    static let launchAtLogin = "Opens Unplug when you log in."
    static let keepOffAfterRestart = "Turns the displays you left off back off when Unplug opens at login. It never turns off your last screen."
    static let showInMenuBar = "Shows Unplug's icon in the menu bar."
    static let showInDock = "Uses Unplug as a regular app, with a Dock icon and a window."
    static let automaticUpdates = "Checks for a new version once a day and asks before installing it."
}
