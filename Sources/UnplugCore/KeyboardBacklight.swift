import Foundation
import ObjectiveC

/// Turns the MacBook keyboard backlight off while the built-in display is
/// disconnected, and restores it afterwards.
///
/// Apple has no public API for the keyboard backlight. This uses the private
/// `KeyboardBrightnessClient` class from CoreBrightness, the same one Control
/// Center uses. Every selector is checked at runtime, so if Apple renames
/// anything the feature quietly does nothing instead of crashing.
public enum KeyboardBacklight {
    /// Saved per keyboard, so a later `restore()` (possibly from the other
    /// process: CLI vs. menu bar app) puts back exactly what the user had.
    struct Saved: Codable {
        let keyboardID: UInt64
        let brightness: Float
        let autoBrightness: Bool
    }

    private typealias GetFloat = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFloat = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias GetBool = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias SetBool = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool

    private static let client: NSObject? = {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        return type.init()
    }()

    static let fileURL = DisplayStore.shared.fileURL
        .deletingLastPathComponent()
        .appendingPathComponent("keyboard-backlight.json")

    private static func function<T>(_ name: String, as _: T.Type) -> (NSObject, Selector, T)? {
        let selector = NSSelectorFromString(name)
        guard let client, client.responds(to: selector), let imp = client.method(for: selector)
        else { return nil }
        return (client, selector, unsafeBitCast(imp, to: T.self))
    }

    public static var isAvailable: Bool {
        function("setBrightness:forKeyboard:", as: SetFloat.self) != nil && !keyboardIDs().isEmpty
    }

    static func keyboardIDs() -> [UInt64] {
        let selector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let client, client.responds(to: selector),
              let ids = client.perform(selector)?.takeUnretainedValue() as? [NSNumber]
        else { return [] }
        return ids.map(\.uint64Value)
    }

    /// True while Unplug has the backlight turned off (it holds a saved level).
    public static var isOff: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Turns the backlight on or off on the user's request, independently of
    /// the built-in display.
    public static func setOn(_ on: Bool) {
        if on {
            UnplugSettings.keyboardBacklightOffByUser = false
            restore()
        } else {
            turnOff()
            UnplugSettings.keyboardBacklightOffByUser = true
        }
    }

    /// Saves the current level and turns every keyboard backlight off. Auto
    /// brightness is disabled too, otherwise the light sensor turns it back on.
    public static func turnOff() {
        guard let get = function("brightnessForKeyboard:", as: GetFloat.self),
              let set = function("setBrightness:forKeyboard:", as: SetFloat.self)
        else { return }
        let isAuto = function("isAutoBrightnessEnabledForKeyboard:", as: GetBool.self)
        let setAuto = function("enableAutoBrightness:forKeyboard:", as: SetBool.self)

        // Don't overwrite an earlier save with the already-dimmed state.
        if FileManager.default.fileExists(atPath: fileURL.path) { return }

        var saved: [Saved] = []
        for id in keyboardIDs() {
            let auto = isAuto.map { $0.2($0.0, $0.1, id) } ?? false
            saved.append(Saved(keyboardID: id, brightness: get.2(get.0, get.1, id), autoBrightness: auto))
            if let setAuto { _ = setAuto.2(setAuto.0, setAuto.1, false, id) }
            _ = set.2(set.0, set.1, 0, id)
        }
        if let data = try? JSONEncoder().encode(saved) {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Puts back the brightness and auto-brightness saved by `turnOff()`.
    public static func restore() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([Saved].self, from: data)
        else { return }
        try? FileManager.default.removeItem(at: fileURL)

        let set = function("setBrightness:forKeyboard:", as: SetFloat.self)
        let setAuto = function("enableAutoBrightness:forKeyboard:", as: SetBool.self)
        for item in saved {
            if let set { _ = set.2(set.0, set.1, item.brightness, item.keyboardID) }
            if item.autoBrightness, let setAuto {
                _ = setAuto.2(setAuto.0, setAuto.1, true, item.keyboardID)
            }
        }
    }
}
