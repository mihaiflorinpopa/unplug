import Foundation

/// Preferences shared by the menu bar app and the CLI. The app's own defaults
/// domain is its bundle identifier, so the CLI reads that suite. The app uses
/// `.standard`, since Apple's docs say not to pass your own bundle identifier.
public enum UnplugSettings {
    public static let domain = "io.github.mihaiflorinpopa.unplug"
    static let defaults: UserDefaults =
        Bundle.main.bundleIdentifier == domain ? .standard : UserDefaults(suiteName: domain) ?? .standard

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

    public static let builtinOffWithExternalKey = "builtinOffWithExternal"

    /// Turn the built-in screen off when an external display connects, and
    /// back on when the last one disconnects.
    public static var builtinOffWithExternal: Bool {
        get { defaults.bool(forKey: builtinOffWithExternalKey) }
        set { defaults.set(newValue, forKey: builtinOffWithExternalKey) }
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
