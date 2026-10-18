/// Decides what happens to the built-in screen after a display change: it
/// turns off when a monitor is plugged in, if the user asked for that, and it
/// always comes back when the last monitor goes away, so the Mac is never left
/// without a screen. Makes no display calls itself, so it can be tested.
public struct BuiltinFollower {
    public enum Action: Equatable {
        case none
        case turnOn
        case turnOff
    }

    /// External displays that were on at the last change, to notice one being
    /// plugged in or the last one going away.
    private var externalCount: Int
    /// Set when the last external display goes away while the built-in screen
    /// is off, until the built-in screen is back on.
    public private(set) var restorePending = false

    public init(_ displays: [Display]) {
        externalCount = Self.externals(displays)
    }

    /// Call after every display change (and on wake) with the current displays.
    public mutating func update(_ displays: [Display], turnOffWithExternal: Bool) -> Action {
        let externals = Self.externals(displays)
        defer { externalCount = externals }
        guard let builtin = displays.first(where: \.isBuiltin) else { return .none }
        if externals > 0 {
            restorePending = false
        } else if externalCount > 0, !builtin.isConnected {
            restorePending = true
        }
        if restorePending {
            if !builtin.isConnected { return .turnOn }
            restorePending = false
        } else if externalCount == 0, externals > 0, builtin.isConnected, turnOffWithExternal {
            return .turnOff
        }
        return .none
    }

    /// The built-in screen is back on, so nothing is pending any more.
    public mutating func restored() {
        restorePending = false
    }

    private static func externals(_ displays: [Display]) -> Int {
        displays.filter { !$0.isBuiltin && $0.isConnected }.count
    }
}
