import SwiftUI

/// A toggle with its option's one-line description under the title.
struct OptionToggle: View {
    let option: Option
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                Text(option.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Each option's title and description, shared by the menu and Settings. The
/// Help Book (Resources/Unplug.help) describes them in its own words.
struct Option {
    let title: String
    let detail: String

    static let builtinOffWithExternal = Option(
        title: "Turn Off When a Monitor Connects",
        detail: "Turns the built-in screen off when you plug in a monitor. It always comes back when the last monitor is unplugged.")
    static let keyboardBacklight = Option(
        title: "Keyboard Backlight",
        detail: "Turns the keyboard backlight on or off.")
    static let keyboardBacklightFollowsBuiltin = Option(
        title: "Turn Off Keyboard Backlight with Screen",
        detail: "The keyboard backlight goes off with the built-in screen and comes back with it.")
    static let reconnectOnQuit = Option(
        title: "Reconnect Displays on Quit",
        detail: "Quitting Unplug turns every display back on.")
    static let shortcuts = Option(
        title: "Keyboard Shortcuts",
        detail: "Shortcuts that work in any app. Click one to change it.")
    static let launchAtLogin = Option(
        title: "Launch at Login",
        detail: "Opens Unplug when you log in.")
    static let keepOffAfterRestart = Option(
        title: "Keep Displays Off",
        detail: "Displays you turned off stay off after a restart and when they're plugged back in. It never turns off your last screen.")
    static let showInMenuBar = Option(
        title: "Show in Menu Bar",
        detail: "Shows Unplug's icon in the menu bar.")
    static let showInDock = Option(
        title: "Show in Dock",
        detail: "Uses Unplug as a regular app, with a Dock icon and a window.")
    static let automaticUpdates = Option(
        title: "Check for Updates Automatically",
        detail: "Checks for a new version when Unplug opens and once a day, and asks before installing it.")
}
