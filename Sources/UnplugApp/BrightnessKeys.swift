import AppKit
import ApplicationServices
import SwiftUI
import UnplugCore

/// Makes the keyboard's brightness keys work on external monitors macOS can't
/// dim itself. The keys act on the screen under the pointer; for the built-in
/// screen and Apple displays they pass through to macOS untouched.
///
/// Uses an event tap, which needs the Accessibility permission. The tap only
/// runs when a key is pressed, so it costs nothing while idle.
final class BrightnessKeys {
    /// External displays Unplug can dim with DDC, by display ID. Set on the main thread.
    var targets: Set<CGDirectDisplayID> = []
    /// Called on the main thread with the display ID and +1 or -1.
    var onStep: ((CGDirectDisplayID, Int) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks for the Accessibility permission, showing macOS's prompt if needed.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    /// Starts listening. Returns false while the Accessibility permission is missing.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << 14) | CGEventMask(1 << CGEventType.keyDown.rawValue) // 14: NX_SYSDEFINED
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let keys = Unmanaged<BrightnessKeys>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = keys.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let step = BrightnessKeys.brightnessStep(type, event),
              let displayID = BrightnessKeys.displayUnderPointer(), keys.targets.contains(displayID)
        else { return Unmanaged.passUnretained(event) }
        keys.onStep?(displayID, step)
        return nil // handled: don't let macOS also act on it
    }

    /// +1 / -1 for a brightness key press, nil for anything else.
    private static func brightnessStep(_ type: CGEventType, _ event: CGEvent) -> Int? {
        if type == .keyDown {
            // Some keyboards send the brightness keys as key codes 144 and 145.
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case 144: return 1
            case 145: return -1
            default: return nil
            }
        }
        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8
        else { return nil }
        let keyCode = (nsEvent.data1 & 0xFFFF_0000) >> 16
        let isDown = (nsEvent.data1 & 0xFF00) >> 8 == 0x0A
        guard isDown else { return nil }
        switch keyCode {
        case 2: return 1 // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: return -1 // NX_KEYTYPE_BRIGHTNESS_DOWN
        default: return nil
        }
    }

    private static func displayUnderPointer() -> CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// A small on-screen indicator like the one macOS shows for its own displays.
@MainActor
final class BrightnessHUD {
    private var panel: NSPanel?
    private var hide: Task<Void, Never>?

    func show(_ level: Double, on displayID: CGDirectDisplayID) {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        } ?? NSScreen.main
        guard let screen else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: BrightnessHUDView(level: level))
        let size = NSSize(width: 200, height: 200)
        panel.setFrame(NSRect(
            x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 140,
            width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()

        hide?.cancel()
        hide = Task { @MainActor [weak panel] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }
}

private struct BrightnessHUDView: View {
    let level: Double

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 56))
            ProgressView(value: level)
                .frame(width: 140)
            Text("\(Int((level * 100).rounded()))%")
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
