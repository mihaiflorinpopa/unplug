import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import UnplugCore

@MainActor
final class DisplaysModel: ObservableObject {
    static let reconnectOnQuitKey = "reconnectOnQuit"
    static let shortcutsKey = "globalShortcuts"
    static let showInMenuBarKey = "showInMenuBar"
    static let showInDockKey = "showInDock"
    static let brightnessKeysKey = "brightnessKeys"

    @Published private(set) var displays: [Display] = []
    @Published var lastError: String?
    /// Disconnected displays whose reconnect failed, usually because they were
    /// unplugged. The menu offers to forget them.
    @Published private(set) var unreachable: Set<String> = []
    /// Brightness (0–1) by display UUID, for displays that support it. Read when
    /// the menu or window opens; monitors are never polled.
    @Published private(set) var brightness: [String: Double] = [:]
    @AppStorage(reconnectOnQuitKey) var reconnectOnQuit = true

    private let manager = DisplayManager()
    private var monitor: DisplayMonitor?
    private let hotKeys = HotKeys()
    private var menuObserver: NSObjectProtocol?
    private let brightnessControl = Brightness()
    /// DDC can take a moment per call, so brightness I/O runs on its own queue.
    private let brightnessQueue = DispatchQueue(label: "io.github.mihaiflorinpopa.unplug.brightness")
    private var pendingBrightness: [String: (Display, Double)] = [:]
    private let brightnessKeys = BrightnessKeys()
    private let hud = BrightnessHUD()

    /// Called when "Show in Dock" changes, so the app delegate can switch between
    /// a menu bar–only app and a regular app with a Dock icon and a window.
    var onShowInDockChange: ((Bool) -> Void)?

    init() {
        refresh()
        monitor = DisplayMonitor { [weak self] in
            Task { @MainActor in
                self?.brightnessControl.reset()
                self?.refresh()
                if self?.brightnessKeysEnabled == true { self?.refreshBrightness() }
            }
        }
        // Re-read state each time the menu opens, so changes made elsewhere
        // (the CLI, the keyboard's brightness keys) show up.
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.refreshBrightness()
                self?.startBrightnessKeysIfAllowed()
                self?.objectWillChange.send()
            }
        }
        applyShortcuts()
        brightnessKeys.onStep = { [weak self] displayID, step in
            Task { @MainActor in self?.stepBrightness(displayID, step) }
        }
        if brightnessKeysEnabled {
            startBrightnessKeysIfAllowed()
            refreshBrightness()
        }
    }

    func refresh() {
        displays = manager.displays()
        // A display that is back online no longer needs forgetting.
        unreachable.formIntersection(displays.filter { !$0.isConnected }.map(\.uuid))
    }

    /// Reads every connected display's brightness in the background.
    func refreshBrightness() {
        let displays = self.displays.filter(\.isConnected)
        let control = brightnessControl
        brightnessQueue.async { [weak self] in
            var levels: [String: Double] = [:]
            var keyTargets: Set<CGDirectDisplayID> = []
            for display in displays {
                guard let level = control.get(display) else { continue }
                levels[display.uuid] = level
                if !Brightness.isHandledByMacOS(display.displayID) { keyTargets.insert(display.displayID) }
            }
            Task { @MainActor in
                self?.brightness = levels
                self?.brightnessKeys.targets = keyTargets
            }
        }
    }

    /// Updates the slider at once and sends only the latest value to the
    /// display, so dragging doesn't queue up a backlog of slow DDC writes.
    func setBrightness(_ display: Display, _ level: Double) {
        brightness[display.uuid] = level
        let isIdle = pendingBrightness.isEmpty
        pendingBrightness[display.uuid] = (display, level)
        guard isIdle else { return }
        sendPendingBrightness()
    }

    private func sendPendingBrightness() {
        guard let (uuid, (display, level)) = pendingBrightness.first else { return }
        let control = brightnessControl
        brightnessQueue.async { [weak self] in
            control.set(display, level)
            Task { @MainActor in
                guard let self else { return }
                if let latest = self.pendingBrightness[uuid], latest.1 == level {
                    self.pendingBrightness[uuid] = nil
                }
                self.sendPendingBrightness()
            }
        }
    }

    /// A brightness key press on an external display: one of 16 steps, like macOS.
    func stepBrightness(_ displayID: CGDirectDisplayID, _ step: Int) {
        guard let display = displays.first(where: { $0.displayID == displayID && $0.isConnected }),
              let current = brightness[display.uuid]
        else { return }
        let level = min(max(((current * 16).rounded() + Double(step)) / 16, 0), 1)
        setBrightness(display, level)
        hud.show(level, name: display.name, on: displayID)
    }

    /// Brightness keys for external monitors. Needs the Accessibility permission.
    var brightnessKeysEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.brightnessKeysKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.brightnessKeysKey)
            if newValue {
                if !BrightnessKeys.isTrusted { BrightnessKeys.requestTrust() }
                startBrightnessKeysIfAllowed()
                refreshBrightness()
            } else {
                brightnessKeys.stop()
                lastError = nil
            }
            objectWillChange.send()
        }
    }

    /// Starts the key listener once the Accessibility permission is granted.
    /// Checked again each time the menu opens, so granting it takes effect then.
    private func startBrightnessKeysIfAllowed() {
        guard brightnessKeysEnabled, !brightnessKeys.isRunning else { return }
        if BrightnessKeys.isTrusted, brightnessKeys.start() {
            lastError = nil
        } else {
            lastError = "To use the brightness keys, allow Unplug in System Settings > Privacy & Security > Accessibility."
        }
    }

    func setConnected(_ display: Display, _ connected: Bool) {
        do {
            if connected {
                try manager.connect(display)
            } else {
                try manager.disconnect(display)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if connected { unreachable.insert(display.uuid) }
        }
        refresh()
    }

    func connectAll() {
        let failures = manager.connectAll()
        lastError = failures.first.map { $0.1.localizedDescription }
        unreachable.formUnion(failures.map { $0.0.uuid })
        refresh()
    }

    func forget(_ display: Display) {
        manager.forget(display)
        unreachable.remove(display.uuid)
        lastError = nil
        refresh()
    }

    func toggleBuiltin() {
        guard let display = displays.first(where: \.isBuiltin) else { return NSSound.beep() }
        setConnected(display, !display.isConnected)
        if lastError != nil { NSSound.beep() }
    }

    let keyboardBacklightAvailable = KeyboardBacklight.isAvailable

    var keyboardLightOn: Bool {
        get { !KeyboardBacklight.isOff }
        set {
            KeyboardBacklight.setOn(newValue)
            objectWillChange.send()
        }
    }

    var keyboardBacklightFollowsBuiltin: Bool {
        get { UnplugSettings.keyboardBacklightFollowsBuiltin }
        set {
            UnplugSettings.keyboardBacklightFollowsBuiltin = newValue
            objectWillChange.send()
        }
    }

    /// System-wide shortcuts: Control-Option-Command-U reconnects every display,
    /// Control-Option-Command-B turns the built-in screen off or on.
    var shortcutsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.shortcutsKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.shortcutsKey)
            applyShortcuts()
            objectWillChange.send()
        }
    }

    private func applyShortcuts() {
        hotKeys.unregisterAll()
        guard shortcutsEnabled else { return }
        let modifiers = controlKey | optionKey | cmdKey
        hotKeys.register(keyCode: kVK_ANSI_U, modifiers: modifiers) { [weak self] in
            Task { @MainActor in self?.connectAll() }
        }
        hotKeys.register(keyCode: kVK_ANSI_B, modifiers: modifiers) { [weak self] in
            Task { @MainActor in self?.toggleBuiltin() }
        }
    }

    var showInMenuBar: Bool {
        get { UserDefaults.standard.object(forKey: Self.showInMenuBarKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.showInMenuBarKey)
            // Keep at least one way to reach the app.
            if !newValue && !showInDock { showInDock = true }
            objectWillChange.send()
        }
    }

    var showInDock: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showInDockKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.showInDockKey)
            if !newValue && !showInMenuBar { showInMenuBar = true }
            onShowInDockChange?(newValue)
            objectWillChange.send()
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                lastError = error.localizedDescription
            }
            objectWillChange.send()
        }
    }
}
