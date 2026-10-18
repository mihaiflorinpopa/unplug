import CoreGraphics
import Foundation

/// The only private API Unplug uses to disconnect displays, isolated here so it
/// is easy to audit and to fix if Apple changes it.
///
/// `CGSConfigureDisplayEnabled` is exported by CoreGraphics (re-exported from
/// SkyLight). It adds an "enabled" change to a regular, documented display
/// configuration transaction (`CGBeginDisplayConfiguration` /
/// `CGCompleteDisplayConfiguration`). On Apple Silicon with macOS 13 or later a
/// disabled display is torn down completely: it leaves the online display list
/// and stops using GPU resources until it is enabled again.
enum SkyLight {
    private typealias ConfigureDisplayEnabled =
        @convention(c) (OpaquePointer?, CGDirectDisplayID, Bool) -> Int32

    private static let configureDisplayEnabled: ConfigureDisplayEnabled? = {
        let path = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, "CGSConfigureDisplayEnabled")
        else { return nil }
        return unsafeBitCast(symbol, to: ConfigureDisplayEnabled.self)
    }()

    static var isAvailable: Bool { configureDisplayEnabled != nil }

    static func configure(
        _ config: CGDisplayConfigRef?, display: CGDirectDisplayID, enabled: Bool
    ) -> CGError {
        guard let fn = configureDisplayEnabled else { return .cannotComplete }
        return CGError(rawValue: fn(config, display, enabled)) ?? .failure
    }
}
