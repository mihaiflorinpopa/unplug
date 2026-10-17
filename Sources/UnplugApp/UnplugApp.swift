import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import UnplugCore

@main
struct UnplugApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = DisplaysModel()

    var body: some Scene {
        MenuBarExtra("Unplug", systemImage: "display.2") {
            MenuContent(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        if UserDefaults.standard.object(forKey: DisplaysModel.reconnectOnQuitKey) as? Bool ?? true {
            DisplayManager().connectAll()
        }
    }
}

@MainActor
final class DisplaysModel: ObservableObject {
    static let reconnectOnQuitKey = "reconnectOnQuit"
    static let shortcutsKey = "globalShortcuts"

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

struct MenuContent: View {
    @ObservedObject var model: DisplaysModel

    private var builtin: [Display] { model.displays.filter(\.isBuiltin) }
    private var external: [Display] { model.displays.filter { !$0.isBuiltin } }

    var body: some View {
        // The built-in display and the keyboard light it controls, together.
        ForEach(builtin) { display in
            Section(display.name) {
                Toggle("Screen", isOn: connected(display))
                if model.keyboardBacklightAvailable {
                    Toggle("Keyboard Light", isOn: $model.keyboardLightOn)
                    Toggle("Turn Off Keyboard Light with Screen", isOn: $model.keyboardBacklightFollowsBuiltin)
                }
            }
        }

        if !external.isEmpty {
            if !builtin.isEmpty { Divider() }
            Section("External Displays") {
                ForEach(external) { display in
                    Toggle(display.name, isOn: connected(display))
                    if model.unreachable.contains(display.uuid) {
                        Button("Forget \(display.name)") { model.forget(display) }
                    }
                }
            }
        }

        if let error = model.lastError {
            Divider()
            Text(error)
        }

        Divider()
        if model.displays.contains(where: { !$0.isConnected }) {
            Button("Reconnect All Displays") { model.connectAll() }
        }
        Menu("Options") {
            Toggle("Reconnect Displays on Quit", isOn: $model.reconnectOnQuit)
            Toggle("Keyboard Shortcuts (⌃⌥⌘U, ⌃⌥⌘B)", isOn: $model.shortcutsEnabled)
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
        }
        Divider()
        Text("Unplug \(UnplugVersion.current)")
        Button("Quit Unplug") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func connected(_ display: Display) -> Binding<Bool> {
        Binding(
            get: { display.isConnected },
            set: { model.setConnected(display, $0) }
        )
    }
}
