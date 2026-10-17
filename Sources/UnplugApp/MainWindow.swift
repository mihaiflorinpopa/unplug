import AppKit
import SwiftUI
import UnplugCore

/// The window for people who prefer a regular app to a menu bar app. It shows
/// the same controls as the menu. Kept alive when closed so reopening is instant.
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    private let model: DisplaysModel
    private let updater: Updater
    private var window: NSWindow?

    init(model: DisplaysModel, updater: Updater) {
        self.model = model
        self.updater = updater
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: MainWindowView(model: model, updater: updater)))
        window.title = "Unplug"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 420, height: 560))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// Picks up changes made elsewhere (the CLI).
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
        model.refreshBrightness()
    }
}

struct MainWindowView: View {
    @ObservedObject var model: DisplaysModel
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            DisplaySections(model: model)

            if model.displays.contains(where: { !$0.isConnected }) {
                Section {
                    Button("Reconnect All Displays") { model.connectAll() }
                }
            }

            if let error = model.lastError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section("Options") {
                Toggle("Reconnect Displays on Quit", isOn: $model.reconnectOnQuit)
                Toggle("Keyboard Shortcuts (⌃⌥⌘U, ⌃⌥⌘B)", isOn: $model.shortcutsEnabled)
                Toggle("Launch at Login", isOn: $model.launchAtLogin)
                Toggle("Keep Displays Off After Restart", isOn: $model.keepOffAfterRestart)
                Toggle("Show in Menu Bar", isOn: $model.showInMenuBar)
                Toggle("Show in Dock", isOn: $model.showInDock)
            }

            Section {
                if updater.isAvailable {
                    Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecks)
                }
                LabeledContent("Version \(UnplugVersion.current)") {
                    if updater.isAvailable {
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .disabled(!updater.canCheck)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 420)
    }
}
