import AppKit
import Carbon.HIToolbox
import os
import ServiceManagement
import SwiftUI
import UnplugCore

@MainActor
final class DisplaysModel: ObservableObject {
    static let reconnectOnQuitKey = "reconnectOnQuit"
    static let shortcutsKey = "globalShortcuts"
    static let showInMenuBarKey = "showInMenuBar"
    static let showInDockKey = "showInDock"

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

    /// Called when "Show in Dock" changes, so the app delegate can switch between
    /// a menu bar–only app and a regular app with a Dock icon and a window.
    var onShowInDockChange: ((Bool) -> Void)?

    /// Displays still to turn off again after a restart. Some monitors come
    /// online a moment after login, so this is retried on each display change.
    private var pendingTurnOff: Set<String> = []
    /// Decides when the built-in screen turns off or back on with monitors.
    private var follower = BuiltinFollower([])
    private var builtinRestoreRetry: Task<Void, Never>?
    private var wakeObservers: [NSObjectProtocol] = []
    /// What Unplug did to the built-in screen and why. See it with
    /// `log show --last 10m --predicate 'subsystem == "io.github.mihaiflorinpopa.unplug"'`.
    private let log = Logger(subsystem: "io.github.mihaiflorinpopa.unplug", category: "displays")

    init() {
        if UnplugSettings.keepOffAfterRestart {
            pendingTurnOff = UnplugSettings.turnedOff
            turnOffPending()
        }
        refresh()
        follower = BuiltinFollower(displays)
        monitor = DisplayMonitor { [weak self] in
            Task { @MainActor in
                self?.turnOffPending()
                self?.brightnessControl.reset()
                self?.refresh()
                self?.followExternalDisplays()
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
                self?.objectWillChange.send()
            }
        }
        // A Mac left with no screen can go to display sleep, or sleep entirely
        // with the lid closed, before the built-in screen comes back, so check
        // again when displays or the Mac wake.
        wakeObservers = [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification].map {
            NSWorkspace.shared.notificationCenter.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                    self?.followExternalDisplays()
                }
            }
        }
        applyShortcuts()
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
            for display in displays {
                guard let level = control.get(display) else { continue }
                levels[display.uuid] = level
            }
            Task { @MainActor in self?.brightness = levels }
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

    private func turnOffPending() {
        // Turning a display back on in the meantime (CLI included) cancels it.
        pendingTurnOff.formIntersection(UnplugSettings.turnedOff)
        pendingTurnOff = pendingTurnOff.filter { !manager.turnOffAgain(uuid: $0) }
    }

    /// Turns the built-in screen off when an external display is plugged in, if
    /// the user asked for that. Whatever the setting, the built-in screen comes
    /// back when the last external display goes away, so the Mac is never left
    /// without a screen.
    private func followExternalDisplays() {
        switch follower.update(displays, turnOffWithExternal: UnplugSettings.builtinOffWithExternal) {
        case .turnOn:
            log.notice("No monitor is on and the built-in screen is off, so it's turning back on")
            restoreBuiltin(attempt: 0)
        case .turnOff:
            guard let builtin = displays.first(where: \.isBuiltin) else { return }
            do {
                try manager.disconnect(builtin)
                log.notice("A monitor connected, so the built-in screen turned off")
            } catch {
                log.error("Couldn't turn the built-in screen off: \(error.localizedDescription, privacy: .public)")
            }
            refresh()
        case .none:
            builtinRestoreRetry?.cancel()
        }
    }

    /// Turns the built-in screen back on. Right after the last monitor goes,
    /// macOS can still be reconfiguring and reject the change, so a failed try
    /// is repeated a few times, a few seconds apart, and on the next display
    /// change or wake. Nothing runs once it succeeds.
    private func restoreBuiltin(attempt: Int) {
        builtinRestoreRetry?.cancel()
        guard follower.restorePending, let builtin = displays.first(where: \.isBuiltin) else { return }
        guard !builtin.isConnected else {
            follower.restored()
            return
        }
        do {
            try manager.connect(builtin)
            follower.restored()
            log.notice("The built-in screen is back on (try \(attempt + 1))")
        } catch {
            log.error("Try \(attempt + 1) to turn the built-in screen on failed: \(error.localizedDescription, privacy: .public)")
            guard attempt < 5 else {
                log.error("Gave up for now; trying again on the next display change or wake")
                return
            }
            builtinRestoreRetry = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
                self.restoreBuiltin(attempt: attempt + 1)
            }
        }
        refresh()
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

    /// System-wide shortcuts: one reconnects every display, one turns the
    /// built-in screen off or on. ⌃⌥⌘U and ⌃⌥⌘B unless changed.
    var shortcutsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.shortcutsKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.shortcutsKey)
            applyShortcuts()
            objectWillChange.send()
        }
    }

    var reconnectAllShortcut: Shortcut {
        get { Self.loadShortcut("shortcut.reconnectAll") ?? .reconnectAll }
        set { saveShortcut(newValue, "shortcut.reconnectAll") }
    }

    var toggleBuiltinShortcut: Shortcut {
        get { Self.loadShortcut("shortcut.toggleBuiltin") ?? .toggleBuiltin }
        set { saveShortcut(newValue, "shortcut.toggleBuiltin") }
    }

    /// Both shortcuts as shown in the menu, such as "⌃⌥⌘U, ⌃⌥⌘B".
    var shortcutsSummary: String {
        "\(reconnectAllShortcut.description), \(toggleBuiltinShortcut.description)"
    }

    /// Lets the shortcut recorder see keys that are currently shortcuts.
    func pauseShortcuts(_ paused: Bool) {
        if paused { hotKeys.unregisterAll() } else { applyShortcuts() }
    }

    private static func loadShortcut(_ key: String) -> Shortcut? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    private func saveShortcut(_ shortcut: Shortcut, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: key)
        applyShortcuts()
        objectWillChange.send()
    }

    private func applyShortcuts() {
        hotKeys.unregisterAll()
        guard shortcutsEnabled else { return }
        var taken: [String] = []
        let reconnect = reconnectAllShortcut
        if !hotKeys.register(keyCode: reconnect.keyCode, modifiers: reconnect.modifiers, action: { [weak self] in
            Task { @MainActor in self?.connectAll() }
        }) { taken.append(reconnect.description) }
        let builtin = toggleBuiltinShortcut
        if !hotKeys.register(keyCode: builtin.keyCode, modifiers: builtin.modifiers, action: { [weak self] in
            Task { @MainActor in self?.toggleBuiltin() }
        }) { taken.append(builtin.description) }
        if !taken.isEmpty {
            lastError = "\(taken.joined(separator: " and ")) already belongs to another app. Choose another shortcut in Options."
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

    var builtinOffWithExternal: Bool {
        get { UnplugSettings.builtinOffWithExternal }
        set {
            UnplugSettings.builtinOffWithExternal = newValue
            objectWillChange.send()
        }
    }

    /// Turns displays the user left off back off when Unplug starts. Needs
    /// Unplug to open at login, so turning it on also turns that on.
    var keepOffAfterRestart: Bool {
        get { UnplugSettings.keepOffAfterRestart }
        set {
            UnplugSettings.keepOffAfterRestart = newValue
            if newValue && !launchAtLogin { launchAtLogin = true }
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
            // macOS can hold a new login item until the user allows it.
            if newValue && SMAppService.mainApp.status == .requiresApproval {
                lastError = "Allow Unplug under Login Items in System Settings so it can open at login."
                SMAppService.openSystemSettingsLoginItems()
            }
            objectWillChange.send()
        }
    }
}
