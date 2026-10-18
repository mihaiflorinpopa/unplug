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
        NSApp.activate()
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

