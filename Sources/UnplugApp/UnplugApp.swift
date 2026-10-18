import AppKit
import SwiftUI
import UnplugCore

@main
struct UnplugApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @AppStorage(DisplaysModel.showInMenuBarKey) private var showInMenuBar = true

    var body: some Scene {
        MenuBarExtra("Unplug", systemImage: "display.2", isInserted: $showInMenuBar) {
            MenuContent(model: delegate.model, showSettings: { delegate.window.show() },
                        showAbout: { delegate.about.show() }, showHelp: { delegate.help.show() })
        }
        .commands {
            // The app menu and Help menu, seen when Unplug runs with a Dock icon.
            CommandGroup(replacing: .appInfo) {
                Button("About Unplug") { delegate.about.show() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.window.show() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) {
                Button("Unplug Help") { delegate.help.show() }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = DisplaysModel()
    let updater = Updater()
    /// The window with every option, opened with Settings… or from the Dock.
    private(set) lazy var window = MainWindow(model: model, updater: updater)
    let about = SimpleWindow(title: "About Unplug") { AboutView() }
    let help = SimpleWindow(title: "Unplug Help") { HelpView() }

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
