import AppKit
import SwiftUI
import UnplugCore

@main
struct UnplugApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @AppStorage(DisplaysModel.showInMenuBarKey) private var showInMenuBar = true

    var body: some Scene {
        MenuBarExtra("Unplug", systemImage: "display.2", isInserted: $showInMenuBar) {
            MenuContent(model: delegate.model, updater: delegate.updater)
        }
        // Gives the app menu its Settings… item (⌘,). Help comes from the
        // Help Book named in Info.plist, and About from the standard panel.
        Settings {
            SettingsView(model: delegate.model, updater: delegate.updater)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = DisplaysModel()
    let updater = Updater()
    private lazy var window = MainWindow(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onShowInDockChange = { [weak self] in self?.setShowsInDock($0) }
        if model.showInDock || !model.showInMenuBar { setShowsInDock(true) }
    }

    /// The app starts as a menu bar app (LSUIElement); "Show in Dock" turns it
    /// into a regular app with a Dock icon and opens the window.
    private func setShowsInDock(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if show { window.show() }
    }

    /// Opening Unplug again (Dock icon, Finder, Spotlight) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.show()
        return true
    }

    /// Control-clicking the Dock icon turns displays off or on. Built each
    /// time, so it shows the current state.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        model.refresh()
        let menu = NSMenu()
        for display in model.displays {
            let item = NSMenuItem(title: display.name, action: #selector(toggleDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = display.uuid
            item.state = display.isConnected ? .on : .off
            menu.addItem(item)
        }
        if model.displays.contains(where: { !$0.isConnected }) {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Reconnect All Displays", action: #selector(reconnectAll), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func toggleDisplay(_ item: NSMenuItem) {
        guard let display = model.displays.first(where: { $0.uuid == item.representedObject as? String }) else { return }
        model.setConnected(display, !display.isConnected)
    }

    @objc private func reconnectAll() {
        model.connectAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if model.reconnectOnQuit {
            // Keep the user's choices, so "Keep Displays Off After Restart" still knows them.
            DisplayManager().connectAll(keepChoices: true)
        }
    }
}
