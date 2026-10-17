import Foundation

/// Preferences shared by the menu bar app and the CLI. The app's own defaults
/// domain is its bundle identifier, so the CLI reads the same suite.
public enum UnplugSettings {
    static let domain = "io.github.mihaiflorinpopa.unplug"
    static let defaults = UserDefaults(suiteName: domain) ?? .standard

    public static let keyboardBacklightKey = "keyboardBacklightFollowsBuiltin"

    /// Turn the keyboard backlight off while the built-in display is disconnected.
    public static var keyboardBacklightFollowsBuiltin: Bool {
        get { defaults.object(forKey: keyboardBacklightKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: keyboardBacklightKey) }
    }

    public static let keepOffAfterRestartKey = "keepOffAfterRestart"

    /// Turn displays the user left off back off when Unplug starts, since
    /// changes only last until logout.
    public static var keepOffAfterRestart: Bool {
        get { defaults.bool(forKey: keepOffAfterRestartKey) }
        set { defaults.set(newValue, forKey: keepOffAfterRestartKey) }
    }

    /// UUIDs of the displays the user turned off and hasn't turned back on.
    public static var turnedOff: Set<String> {
        get { Set(defaults.stringArray(forKey: "turnedOff") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "turnedOff") }
    }

    /// The user turned the keyboard backlight off themselves, so reconnecting the
    /// built-in display must not switch it back on.
    static var keyboardBacklightOffByUser: Bool {
        get { defaults.bool(forKey: "keyboardBacklightOffByUser") }
        set { defaults.set(newValue, forKey: "keyboardBacklightOffByUser") }
    }
}
