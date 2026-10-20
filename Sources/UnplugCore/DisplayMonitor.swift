import CoreGraphics
import Foundation

/// Calls `onChange` after macOS finishes reconfiguring displays (connect,
/// disconnect, enable, disable, mode change), using Apple's documented
/// reconfiguration callback rather than polling. Sendable because its callbacks
/// and `onChange` only run on the main thread.
public final class DisplayMonitor: @unchecked Sendable {
    private let onChange: () -> Void
    /// Set while a call to `onChange` is queued, so the calls macOS makes for
    /// each display in one change lead to one refresh, not one per display.
    private var changeQueued = false

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        CGDisplayRegisterReconfigurationCallback(Self.callback, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(Self.callback, Unmanaged.passUnretained(self).toOpaque())
    }

    private static let callback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        // macOS calls once before the change (beginConfigurationFlag) and once per
        // display after it; only the "after" calls describe the new state.
        guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
        let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        // The calls arrive on the main thread, where the app registered, so the
        // flag needs no lock. It's cleared before `onChange` runs, so a change
        // that comes in meanwhile queues its own refresh.
        guard !monitor.changeQueued else { return }
        monitor.changeQueued = true
        DispatchQueue.main.async {
            monitor.changeQueued = false
            monitor.onChange()
        }
    }
}
