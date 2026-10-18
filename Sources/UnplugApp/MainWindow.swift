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
                OptionToggle(title: "Reconnect Displays on Quit", detail: OptionDetail.reconnectOnQuit,
                             isOn: $model.reconnectOnQuit)
                ShortcutsSettings(model: model)
                OptionToggle(title: "Launch at Login", detail: OptionDetail.launchAtLogin,
                             isOn: $model.launchAtLogin)
                OptionToggle(title: "Keep Displays Off After Restart", detail: OptionDetail.keepOffAfterRestart,
                             isOn: $model.keepOffAfterRestart)
                OptionToggle(title: "Show in Menu Bar", detail: OptionDetail.showInMenuBar,
                             isOn: $model.showInMenuBar)
                OptionToggle(title: "Show in Dock", detail: OptionDetail.showInDock,
                             isOn: $model.showInDock)
            }

            Section {
                if updater.isAvailable {
                    OptionToggle(title: "Check for Updates Automatically", detail: OptionDetail.automaticUpdates,
                                 isOn: $updater.automaticallyChecks)
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
