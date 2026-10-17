import CoreGraphics
import Foundation

/// Calls `onChange` after macOS finishes reconfiguring displays (connect,
/// disconnect, enable, disable, mode change), using Apple's documented
/// reconfiguration callback rather than polling.
public final class DisplayMonitor {
    private let onChange: () -> Void

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
        DispatchQueue.main.async { monitor.onChange() }
    }
}
