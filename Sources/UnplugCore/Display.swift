import AppKit
import CoreGraphics
import Foundation

/// A display Unplug knows about: either online now, or one it disconnected and
/// remembers so it can bring it back.
public struct Display: Codable, Hashable, Identifiable, Sendable {
    /// Stable identity across reboots and re-enumeration (macOS can renumber IDs).
    public let uuid: String
    /// The `CGDirectDisplayID` the display had when it was last seen.
    public var displayID: CGDirectDisplayID
    public var name: String
    public var isBuiltin: Bool
    public var isConnected: Bool

    public var id: String { uuid }

    static func current(_ displayID: CGDirectDisplayID) -> Display? {
        guard let uuid = uuidString(for: displayID) else { return nil }
        return Display(
            uuid: uuid,
            displayID: displayID,
            name: localizedName(for: displayID),
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
            isConnected: true
        )
    }

    static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, ref) as String
    }

    static func localizedName(for displayID: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        }
        if let name = screen?.localizedName { return name }
        return CGDisplayIsBuiltin(displayID) != 0 ? "Built-in Display" : "Display \(displayID)"
    }
}
