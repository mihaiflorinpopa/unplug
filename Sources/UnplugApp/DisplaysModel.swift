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

    @Published private(set) var displays: [Display] = []
    @Published var lastError: String?
    /// Disconnected displays whose reconnect failed, usually because they were
    /// unplugged. The menu offers to forget them.
    @Published private(set) var unreachable: Set<String> = []
    @AppStorage(reconnectOnQuitKey) var reconnectOnQuit = true

    private let manager = DisplayManager()
    private var monitor: DisplayMonitor?
    private let hotKeys = HotKeys()
    private var menuObserver: NSObjectProtocol?

    /// Called when "Show in Dock" changes, so the app delegate can switch between
    /// a menu bar–only app and a regular app with a Dock icon and a window.
    var onShowInDockChange: ((Bool) -> Void)?

    init() {
        refresh()
        monitor = DisplayMonitor { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        // Re-read state each time the menu opens, so changes made elsewhere
        // (the CLI, the keyboard's brightness keys) show up.
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.objectWillChange.send()
            }
        }
        applyShortcuts()
    }

    func refresh() {
        displays = manager.displays()
        // A display that is back online no longer needs forgetting.
        unreachable.formIntersection(displays.filter { !$0.isConnected }.map(\.uuid))
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
