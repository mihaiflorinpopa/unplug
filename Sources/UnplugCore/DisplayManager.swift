import CoreGraphics
import Foundation

public enum UnplugError: LocalizedError, Equatable {
    case privateAPIUnavailable
    case lastActiveDisplay(String)
    case notFound(String)
    case ambiguous(String, [String])
    case alreadyConnected(String)
    case alreadyDisconnected(String)
    case reconnectFailed(String)
    case coreGraphics(CGError)

    public var errorDescription: String? {
        switch self {
        case .privateAPIUnavailable:
            return "This version of macOS does not expose CGSConfigureDisplayEnabled."
        case .lastActiveDisplay(let name):
            return "Refusing to disconnect \(name): it is the last active display. Use --force to override."
        case .notFound(let query):
            return "No display matches \"\(query)\". Run `unplug list` to see displays."
        case .ambiguous(let query, let names):
            return "\"\(query)\" matches several displays: \(names.joined(separator: ", ")). Use the ID or UUID."
        case .alreadyConnected(let name):
            return "\(name) is already connected."
        case .alreadyDisconnected(let name):
            return "\(name) is already disconnected."
        case .reconnectFailed(let name):
            return "Couldn't reconnect \(name). If it was unplugged, forget it with `unplug forget` or Forget in the menu."
        case .coreGraphics(let error):
            return "macOS rejected the display configuration (CGError \(error.rawValue))."
        }
    }
}

/// Lists, disconnects and reconnects displays. Everything except the single
/// private call in `SkyLight` uses documented Quartz Display Services.
public final class DisplayManager {
    let store: DisplayStore

    public init() { self.store = .shared }
    init(store: DisplayStore) { self.store = store }

    /// Online displays plus the ones Unplug disconnected, sorted built-in first.
    public func displays() -> [Display] {
        let online = Self.onlineDisplayIDs().compactMap(Display.current)
        let onlineUUIDs = Set(online.map(\.uuid))

        // A remembered display that is online again (replugged, or reconnected by
        // another tool) no longer needs remembering.
        var remembered = store.load()
        let stale = remembered.filter { onlineUUIDs.contains($0.uuid) }
        if !stale.isEmpty {
            remembered.removeAll { onlineUUIDs.contains($0.uuid) }
            store.save(remembered)
        }

        return (online + remembered).sorted {
            ($0.isBuiltin ? 0 : 1, $0.displayID) < ($1.isBuiltin ? 0 : 1, $1.displayID)
        }
    }

    /// Finds a display by numeric ID, UUID, or a case-insensitive part of its name.
    public func resolve(_ query: String) throws -> Display {
        try Self.match(query, in: displays())
    }

    static func match(_ query: String, in all: [Display]) throws -> Display {
        if let id = UInt32(query), let match = all.first(where: { $0.displayID == id }) {
            return match
        }
        if let match = all.first(where: { $0.uuid.caseInsensitiveCompare(query) == .orderedSame }) {
            return match
        }
        let byName = all.filter { $0.name.localizedCaseInsensitiveContains(query) }
        switch byName.count {
        case 1: return byName[0]
        case 0: throw UnplugError.notFound(query)
        default: throw UnplugError.ambiguous(query, byName.map { "\($0.name) (\($0.displayID))" })
        }
    }

    public func disconnect(_ display: Display, force: Bool = false) throws {
        guard SkyLight.isAvailable else { throw UnplugError.privateAPIUnavailable }
        guard display.isConnected else { throw UnplugError.alreadyDisconnected(display.name) }
        if !force {
            let others = Self.activeDisplayIDs().filter { $0 != display.displayID }
            if others.isEmpty { throw UnplugError.lastActiveDisplay(display.name) }
        }

        // Remember first, so a display is never lost even if we are killed mid-way.
        store.remember(display)
        do {
            try Self.transaction { SkyLight.configure($0, display: display.displayID, enabled: false) }
        } catch {
            store.forget(uuid: display.uuid)
            throw error
        }
        UnplugSettings.turnedOff.insert(display.uuid)
        if display.isBuiltin && UnplugSettings.keyboardBacklightFollowsBuiltin {
            KeyboardBacklight.turnOff()
        }
    }

    /// Reconnects a display. `keepChoice` is for reconnecting on quit: the
    /// display comes back now but still counts as one the user turned off.
    public func connect(_ display: Display, keepChoice: Bool = false) throws {
        guard SkyLight.isAvailable else { throw UnplugError.privateAPIUnavailable }
        guard !display.isConnected else { throw UnplugError.alreadyConnected(display.name) }
        do {
            try Self.transaction { SkyLight.configure($0, display: display.displayID, enabled: true) }
        } catch UnplugError.coreGraphics {
            // Usually the display was unplugged while disconnected, so its old ID
            // no longer exists. Keep remembering it until the user forgets it.
            throw UnplugError.reconnectFailed(display.name)
        }
        store.forget(uuid: display.uuid)
        if !keepChoice { UnplugSettings.turnedOff.remove(display.uuid) }
        if display.isBuiltin && !UnplugSettings.keyboardBacklightOffByUser {
            // Only acts if a disconnect saved the backlight state earlier, and
            // leaves the light off if the user switched it off themselves.
            KeyboardBacklight.restore()
        }
    }

    /// Stops remembering a disconnected display, for one that was unplugged and
    /// can no longer be reconnected. Plugging it back in brings it back anyway.
    public func forget(_ display: Display) {
        store.forget(uuid: display.uuid)
        UnplugSettings.turnedOff.remove(display.uuid)
    }

    /// Turns a display off again if it is online and on, for "Keep Displays Off
    /// After Restart". Returns false when it isn't online yet or is the last
    /// active display, so the caller can try again on the next display change.
    public func turnOffAgain(uuid: String) -> Bool {
        guard let display = Self.onlineDisplayIDs().compactMap(Display.current).first(where: { $0.uuid == uuid })
        else { return false }
        guard display.isConnected else { return true }
        do {
            try disconnect(display)
            return true
        } catch {
            return false
        }
    }

    public func toggle(_ display: Display, force: Bool = false) throws {
        if display.isConnected {
            try disconnect(display, force: force)
        } else {
            try connect(display)
        }
    }

    /// Reconnects every display Unplug disconnected. Returns the ones that failed.
    @discardableResult
    public func connectAll(keepChoices: Bool = false) -> [(Display, Error)] {
        displays().filter { !$0.isConnected }.compactMap { display in
            do {
                try connect(display, keepChoice: keepChoices)
                return nil
            } catch {
                return (display, error)
            }
        }
    }

    // MARK: - Quartz Display Services

    /// Runs one documented configuration transaction. Changes last for the login
    /// session (`.forSession`), so a logout or restart always brings every display
    /// back. App-only scope would undo the change as soon as the CLI exits.
    static func transaction(_ body: (CGDisplayConfigRef?) -> CGError) throws {
        var config: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&config)
        guard error == .success else { throw UnplugError.coreGraphics(error) }

        error = body(config)
        guard error == .success else {
            CGCancelDisplayConfiguration(config)
            throw UnplugError.coreGraphics(error)
        }

        error = CGCompleteDisplayConfiguration(config, .forSession)
        guard error == .success else { throw UnplugError.coreGraphics(error) }
    }

    static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        displayList(CGGetOnlineDisplayList)
    }

    static func activeDisplayIDs() -> [CGDirectDisplayID] {
        displayList(CGGetActiveDisplayList)
    }

    private static func displayList(
        _ get: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    ) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard get(0, nil, &count) == .success, count > 0 else { return [] }
        let capacity = count
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        guard get(capacity, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
