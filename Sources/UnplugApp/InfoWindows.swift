import AppKit
import SwiftUI
import UnplugCore

enum Project {
    static let url = URL(string: "https://github.com/mihaiflorinpopa/unplug")!
    static let authorURL = URL(string: "https://github.com/mihaiflorinpopa")!
}

/// A small window that is created once and brought back on later requests.
@MainActor
final class SimpleWindow {
    private let title: String
    private let makeContent: () -> NSViewController
    private var window: NSWindow?

    init<Content: View>(title: String, content: @escaping () -> Content) {
        self.title = title
        self.makeContent = { NSHostingController(rootView: content()) }
    }

    func show() {
        let window = self.window ?? {
            let window = NSWindow(contentViewController: self.makeContent())
            window.title = self.title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            return window
        }()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Unplug")
                .font(.title2.bold())
            Text("Version \(UnplugVersion.current)" + (UnplugVersion.build.map { " (\($0))" } ?? ""))
                .foregroundStyle(.secondary)
            Text("Disconnect a display without pulling the cable.")
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 6)
            Text("Made by Mihai Florin Popa")
            Link("@mihaiflorinpopa on GitHub", destination: Project.authorURL)
            Link("github.com/mihaiflorinpopa/unplug", destination: Project.url)
            Text("Free and open source under the MIT License.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 340)
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Turn a display off or on",
                        "Click its name in the menu. macOS forgets the display as if you unplugged it, but the cable stays in, so it can keep charging and powering its USB hub.")
                section("Brightness",
                        "Each display that supports it has a brightness control: a submenu in the menu bar, and a slider in the window. Monitors that don't answer brightness commands don't show one.")
                section("Built-in screen and keyboard backlight",
                        "On a MacBook, the built-in screen has its own section. You can turn the keyboard backlight off by itself, or have it go off with the screen and come back with it. Turn on \"Turn Off When a Monitor Connects\" to switch the built-in screen off whenever you plug in a monitor. When the last monitor is unplugged, the built-in screen always comes back on.")
                section("Keyboard shortcuts",
                        "⌃⌥⌘U reconnects every display. ⌃⌥⌘B turns the built-in screen off or on. Change them or turn them off under Options.")
                section("Menu bar or window",
                        "Turn on Options > Show in Dock to use Unplug as a regular app with a window. From the window you can hide the menu bar icon.")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Options").font(.headline)
                    ForEach(Self.options, id: \.0) { title, detail in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).bold()
                            Text(detail).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                section("After a restart",
                        "Logging out or restarting brings every display back. Turn on Options > Keep Displays Off After Restart and Unplug turns the displays you left off back off when it opens at login. It never turns off your last working display.")
                section("If something goes wrong",
                        "Press ⌃⌥⌘U, or quit Unplug: quitting reconnects every display. Logging out or restarting always brings every display back. If you unplugged a display while it was off, choose Forget next to it.")
                section("Command line",
                        "The unplug command is inside the app at Unplug.app/Contents/Helpers/unplug. Link it onto your PATH and run `unplug help`.")
                Link("Full guide on GitHub", destination: Project.url)
            }
            .padding(24)
        }
        .frame(width: 440, height: 520)
    }

    /// Every option, in the order the menu and window show them.
    private static let options: [(String, String)] = [
        ("Turn Off When a Monitor Connects", OptionDetail.builtinOffWithExternal),
        ("Keyboard Backlight", OptionDetail.keyboardBacklight),
        ("Turn Off Keyboard Backlight with Screen", OptionDetail.keyboardBacklightFollowsBuiltin),
        ("Reconnect Displays on Quit", OptionDetail.reconnectOnQuit),
        ("Keyboard Shortcuts", OptionDetail.shortcuts),
        ("Launch at Login", OptionDetail.launchAtLogin),
        ("Keep Displays Off After Restart", OptionDetail.keepOffAfterRestart),
        ("Show in Menu Bar", OptionDetail.showInMenuBar),
        ("Show in Dock", OptionDetail.showInDock),
        ("Check for Updates Automatically", OptionDetail.automaticUpdates),
    ]

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
