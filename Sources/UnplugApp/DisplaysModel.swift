import AppKit
import Carbon.HIToolbox
import os
import ServiceManagement
import SwiftUI
import UnplugCore

@MainActor
@Observable
final class DisplaysModel {
    static let reconnectOnQuitKey = "reconnectOnQuit"
    static let shortcutsKey = "globalShortcuts"
    static let showInMenuBarKey = "showInMenuBar"
    static let showInDockKey = "showInDock"

    private(set) var displays: [Display] = []
    var lastError: String?
    /// Disconnected displays whose reconnect failed, usually because they were
    /// unplugged. The menu offers to forget them.
    private(set) var unreachable: Set<String> = []
    /// Brightness (0–1) by display UUID, for displays that support it. Read when
    /// the menu or window opens; monitors are never polled.
    private(set) var brightness: [String: Double] = [:]
    var reconnectOnQuit: Bool {
        get {
            access(keyPath: \.reconnectOnQuit)
            return UserDefaults.standard.object(forKey: Self.reconnectOnQuitKey) as? Bool ?? true
        }
        set { withMutation(keyPath: \.reconnectOnQuit) { UserDefaults.standard.set(newValue, forKey: Self.reconnectOnQuitKey) } }
    }

    private let manager = DisplayManager()
    @ObservationIgnored private var monitor: DisplayMonitor?
    private let hotKeys = HotKeys()
    private let brightnessControl = Brightness()
    /// DDC can take a moment per call, so brightness I/O runs on its own queue.
    private let brightnessQueue = DispatchQueue(label: "\(UnplugSettings.domain).brightness")
    @ObservationIgnored private var pendingBrightness: [String: (Display, Double)] = [:]

    /// Called when "Show in Dock" changes, so the app delegate can switch between
    /// a menu bar–only app and a regular app with a Dock icon and a window.
    @ObservationIgnored var onShowInDockChange: ((Bool) -> Void)?
    /// Called when "Show in Menu Bar" changes, to show or hide the menu bar item.
    @ObservationIgnored var onShowInMenuBarChange: ((Bool) -> Void)?

    /// Displays still to turn off again ("Keep Displays Off"), after a restart or
    /// when they're plugged back in. Some monitors come
    /// online a moment after login, so this is retried on each display change.
    @ObservationIgnored private var pendingTurnOff: Set<String> = []
    /// Decides when the built-in screen turns off or back on with monitors.
    @ObservationIgnored private var follower = BuiltinFollower([])
    @ObservationIgnored private var builtinRestoreRetry: Task<Void, Never>?
    @ObservationIgnored private var wakeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private var suddenTerminationDisabled = false
    /// The last "shortcut already belongs to another app" message, so it can be
    /// cleared once the shortcuts work, without clearing other errors.
    @ObservationIgnored private var shortcutError: String?
    private let log = DisplayManager.log
    private var builtin: Display? { displays.first(where: \.isBuiltin) }

    init() {
        if UnplugSettings.keepOffAfterRestart {
            pendingTurnOff = UnplugSettings.turnedOff
            turnOffPending()
        }
        refresh()
        follower = BuiltinFollower(displays)
        monitor = DisplayMonitor { [weak self] in
            Task { @MainActor in
                // Keep Displays Off: a display the user turned off stays off when it's
                // plugged back in. Turning it on removes it from turnedOff.
                if UnplugSettings.keepOffAfterRestart { self?.pendingTurnOff = UnplugSettings.turnedOff }
                self?.turnOffPending()
                self?.brightnessControl.reset()
                self?.refresh()
                self?.followExternalDisplays()
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
        // Coming back from System Settings, for example after allowing the login item.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rereadSystemSettings() }
        }
        applyShortcuts()
    }

    func refresh() {
        displays = manager.displays()
        // A display that is back online no longer needs forgetting.
        unreachable.formIntersection(displays.filter { !$0.isConnected }.map(\.uuid))
        updateSuddenTermination()
    }

    /// macOS can end an app at logout without telling it (sudden termination).
    /// While a keyboard backlight level waits to be restored, quitting has work
    /// to do (applicationWillTerminate), so sudden termination is off until then.
    private func updateSuddenTermination() {
        let quitHasWork = reconnectOnQuit && KeyboardBacklight.hasSavedLevel
        guard quitHasWork != suddenTerminationDisabled else { return }
        if quitHasWork {
            ProcessInfo.processInfo.disableSuddenTermination()
        } else {
            ProcessInfo.processInfo.enableSuddenTermination()
        }
        suddenTerminationDisabled = quitHasWork
    }

    /// The menu bar menu opened: re-read what may have changed elsewhere.
    func menuOpened() {
        log.debug("Menu bar menu opened")
        refresh()
        refreshBrightness()
        rereadSystemSettings()
    }

    /// The keyboard's brightness keys or System Settings may have changed these.
    private func rereadSystemSettings() {
        withMutation(keyPath: \.keyboardLightOn) {}
        withMutation(keyPath: \.launchAtLogin) {}
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
            Task { @MainActor in
                guard let self else { return }
                // A level set while this read ran wins over the one read.
                self.brightness = levels.merging(self.pendingBrightness.mapValues { $0.1 }) { $1 }
            }
        }
    }

    /// Updates the slider at once and sends only the latest value to the
    /// display, so dragging doesn't queue up a backlog of slow DDC writes.
    /// Linked displays all take the level.
    func setBrightness(_ display: Display, _ level: Double) {
        let group = linkedDisplays
        let targets = group.contains { $0.uuid == display.uuid } ? group.filter { brightness[$0.uuid] != nil } : [display]
        let isIdle = pendingBrightness.isEmpty
        for target in targets {
            brightness[target.uuid] = level
            pendingBrightness[target.uuid] = (target, level)
        }
        if isIdle { sendPendingBrightness() }
    }

    /// Sends every display's latest level in one go, so one monitor still
    /// being dragged doesn't hold back the others.
    private func sendPendingBrightness() {
        let batch = pendingBrightness
        guard !batch.isEmpty else { return }
        let control = brightnessControl
        brightnessQueue.async { [weak self] in
            for (display, level) in batch.values { control.set(display, level) }
            Task { @MainActor in
                guard let self else { return }
                for (uuid, (_, level)) in batch where self.pendingBrightness[uuid]?.1 == level {
                    self.pendingBrightness[uuid] = nil
                }
                self.sendPendingBrightness()
            }
        }
    }

    /// Displays whose brightness moves together, by UUID, chosen with each
    /// display's Link Brightness switch.
    var linkedBrightness: Set<String> {
        get {
            access(keyPath: \.linkedBrightness)
            return UnplugSettings.linkedBrightness
        }
        set { withMutation(keyPath: \.linkedBrightness) { UnplugSettings.linkedBrightness = newValue } }
    }

    /// The linked displays, once at least two are. The menu shows one slider for them.
    var linkedDisplays: [Display] { displays.linkedGroup(linkedBrightness) }

    /// A display's Link Brightness switch. A display joining takes the level
    /// the linked displays already have.
    func linked(_ display: Display) -> Binding<Bool> {
        Binding(get: { self.linkedBrightness.contains(display.uuid) }, set: { link in
            guard link else {
                self.linkedBrightness.remove(display.uuid)
                return
            }
            let level = self.displays.lazy
                .filter { self.linkedBrightness.contains($0.uuid) }
                .compactMap { self.brightness[$0.uuid] }
                .first
            self.linkedBrightness.insert(display.uuid)
            if let level { self.setBrightness(display, level) }
        })
    }

    private func turnOffPending() {
        // Turning a display back on in the meantime (CLI included) cancels it.
        pendingTurnOff.formIntersection(UnplugSettings.turnedOff)
        pendingTurnOff = pendingTurnOff.filter { uuid in
            guard manager.turnOffAgain(uuid: uuid) else { return true }
            log.notice("Turned a display off again (Keep Displays Off)")
            return false
        }
    }

    /// Turns the built-in screen off when an external display is plugged in, if
    /// the user asked for that. Whatever the setting, the built-in screen comes
    /// back when the last external display goes away, so the Mac is never left
    /// without a screen.
    private func followExternalDisplays() {
        let monitors = displays.filter { !$0.isBuiltin && $0.isConnected }.count
        log.notice("Displays changed: \(monitors) monitor(s) on, built-in screen \(self.builtin?.isConnected == true ? "on" : "off", privacy: .public)")
        switch follower.update(displays, turnOffWithExternal: UnplugSettings.builtinOffWithExternal) {
        case .turnOn:
            log.notice("No monitor is on and the built-in screen is off, so it's turning back on")
            restoreBuiltin(attempt: 0)
        case .turnOff:
            guard let builtin else { return }
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
        guard follower.restorePending, let builtin else { return }
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
                try? await Task.sleep(for: .seconds(attempt + 1))
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

    /// A display's on/off state for a toggle in the menu or the window.
    func connected(_ display: Display) -> Binding<Bool> {
        Binding(get: { display.isConnected }, set: { self.setConnected(display, $0) })
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
        guard let builtin else { return NSSound.beep() }
        setConnected(builtin, !builtin.isConnected)
        if lastError != nil { NSSound.beep() }
    }

    let keyboardBacklightAvailable = KeyboardBacklight.isAvailable

    // Settings stored outside this class (UserDefaults, CoreBrightness,
    // SMAppService) report their reads and writes to Observation themselves,
    // with access(keyPath:) and withMutation(keyPath:), as SE-0395 describes for
    // computed properties backed by other storage.
    var keyboardLightOn: Bool {
        get {
            access(keyPath: \.keyboardLightOn)
            return !KeyboardBacklight.isOff
        }
        set { withMutation(keyPath: \.keyboardLightOn) { KeyboardBacklight.setOn(newValue) } }
    }

    var keyboardBacklightFollowsBuiltin: Bool {
        get {
            access(keyPath: \.keyboardBacklightFollowsBuiltin)
            return UnplugSettings.keyboardBacklightFollowsBuiltin
        }
        set { withMutation(keyPath: \.keyboardBacklightFollowsBuiltin) { UnplugSettings.keyboardBacklightFollowsBuiltin = newValue } }
    }

    /// System-wide shortcuts: one reconnects every display, one turns the
    /// built-in screen off or on. ⌃⌥⌘U and ⌃⌥⌘B unless changed.
    var shortcutsEnabled: Bool {
        get {
            access(keyPath: \.shortcutsEnabled)
            return UserDefaults.standard.object(forKey: Self.shortcutsKey) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.shortcutsEnabled) { UserDefaults.standard.set(newValue, forKey: Self.shortcutsKey) }
            applyShortcuts()
        }
    }

    var reconnectAllShortcut: Shortcut {
        get {
            access(keyPath: \.reconnectAllShortcut)
            return Self.loadShortcut("shortcut.reconnectAll") ?? .reconnectAll
        }
        set { withMutation(keyPath: \.reconnectAllShortcut) { saveShortcut(newValue, "shortcut.reconnectAll") } }
    }

    var toggleBuiltinShortcut: Shortcut {
        get {
            access(keyPath: \.toggleBuiltinShortcut)
            return Self.loadShortcut("shortcut.toggleBuiltin") ?? .toggleBuiltin
        }
        set { withMutation(keyPath: \.toggleBuiltinShortcut) { saveShortcut(newValue, "shortcut.toggleBuiltin") } }
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
    }

    private func applyShortcuts() {
        hotKeys.unregisterAll()
        var taken: [String] = []
        if shortcutsEnabled {
            let reconnect = reconnectAllShortcut
            if !hotKeys.register(keyCode: reconnect.keyCode, modifiers: reconnect.modifiers, action: { [weak self] in
                Task { @MainActor in self?.connectAll() }
            }) { taken.append(reconnect.description) }
            let builtin = toggleBuiltinShortcut
            if !hotKeys.register(keyCode: builtin.keyCode, modifiers: builtin.modifiers, action: { [weak self] in
                Task { @MainActor in self?.toggleBuiltin() }
            }) { taken.append(builtin.description) }
        }
        let error = taken.isEmpty ? nil
            : "\(taken.joined(separator: " and ")) \(taken.count == 1 ? "already belongs" : "already belong") to another app. Choose another shortcut in Settings > Shortcuts."
        // Replace an earlier shortcut error, but leave other errors alone.
        if error != nil || lastError == shortcutError { lastError = error }
        shortcutError = error
    }

    var showInMenuBar: Bool {
        get {
            access(keyPath: \.showInMenuBar)
            return UserDefaults.standard.object(forKey: Self.showInMenuBarKey) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.showInMenuBar) { UserDefaults.standard.set(newValue, forKey: Self.showInMenuBarKey) }
            onShowInMenuBarChange?(newValue)
            // Keep at least one way to reach the app.
            if !newValue && !showInDock { showInDock = true }
        }
    }

    var showInDock: Bool {
        get {
            access(keyPath: \.showInDock)
            return UserDefaults.standard.bool(forKey: Self.showInDockKey)
        }
        set {
            withMutation(keyPath: \.showInDock) { UserDefaults.standard.set(newValue, forKey: Self.showInDockKey) }
            if !newValue && !showInMenuBar { showInMenuBar = true }
            onShowInDockChange?(newValue)
        }
    }

    var builtinOffWithExternal: Bool {
        get {
            access(keyPath: \.builtinOffWithExternal)
            return UnplugSettings.builtinOffWithExternal
        }
        set { withMutation(keyPath: \.builtinOffWithExternal) { UnplugSettings.builtinOffWithExternal = newValue } }
    }

    /// Turns displays the user left off back off when Unplug starts. Needs
    /// Unplug to open at login, so turning it on also turns that on.
    var keepOffAfterRestart: Bool {
        get {
            access(keyPath: \.keepOffAfterRestart)
            return UnplugSettings.keepOffAfterRestart
        }
        set {
            withMutation(keyPath: \.keepOffAfterRestart) { UnplugSettings.keepOffAfterRestart = newValue }
            if newValue && !launchAtLogin { launchAtLogin = true }
        }
    }

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    lastError = error.localizedDescription
                }
            }
            // macOS can hold a new login item until the user allows it.
            if newValue && SMAppService.mainApp.status == .requiresApproval {
                lastError = "Allow Unplug under Login Items in System Settings so it can open at login."
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}
