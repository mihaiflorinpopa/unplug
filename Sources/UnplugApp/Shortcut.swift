import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A keyboard shortcut in the form `RegisterEventHotKey` takes: a virtual key
/// code and Carbon modifier flags.
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int
    /// The key as shown in menus, noted when the shortcut is recorded.
    var key: String

    static let reconnectAll = Shortcut(keyCode: kVK_ANSI_U, modifiers: controlKey | optionKey | cmdKey, key: "U")
    static let toggleBuiltin = Shortcut(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey | cmdKey, key: "B")

    init(keyCode: Int, modifiers: Int, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// The shortcut typed in `event`, or nil if it can't be a global shortcut:
    /// it needs Command, Option or Control, unless it's a function key, so that
    /// ordinary typing is never taken over.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }

        let keyCode = Int(event.keyCode)
        let special = Self.specialKeys[keyCode]
        let isFunctionKey = Self.functionKeys.contains(keyCode)
        guard modifiers & (cmdKey | optionKey | controlKey) != 0 || isFunctionKey else { return nil }
        let key = special ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.isEmpty, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, key: key)
    }

    /// In the order macOS menus show them.
    var description: String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + key
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// Keys that don't type a printable character.
    private static let specialKeys: [Int: String] = {
        var keys: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, code) in functionKeys.enumerated() { keys[code] = "F\(index + 1)" }
        return keys
    }()
}

/// A button that records the next shortcut typed. Escape cancels. Uses a
/// local event monitor, which only sees keys typed into Unplug's own windows
/// and needs no permission.
struct ShortcutRecorder: View {
    let title: String
    @Binding var shortcut: Shortcut
    let defaultShortcut: Shortcut
    /// The other shortcut, which this one can't duplicate.
    let other: Shortcut
    /// Called with true while recording, so the current shortcuts can be paused.
    let onRecording: (Bool) -> Void

    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            HStack {
                if shortcut != defaultShortcut && monitor == nil {
                    Button("Reset") { shortcut = defaultShortcut }
                }
                Button(monitor == nil ? shortcut.description : "Type a shortcut…") {
                    monitor == nil ? start() : stop()
                }
                .frame(minWidth: 110)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
            } else if let recorded = Shortcut(event: event), recorded != other {
                shortcut = recorded
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        onRecording(false)
    }
}

/// The keyboard shortcut settings, shown in the window and in their own
/// window from the menu.
struct ShortcutsSettings: View {
    @ObservedObject var model: DisplaysModel

    var body: some View {
        OptionToggle(title: "Keyboard Shortcuts", detail: OptionDetail.shortcuts, isOn: $model.shortcutsEnabled)
        if model.shortcutsEnabled {
            ShortcutRecorder(
                title: "Reconnect all displays", shortcut: $model.reconnectAllShortcut,
                defaultShortcut: .reconnectAll, other: model.toggleBuiltinShortcut,
                onRecording: model.pauseShortcuts)
            ShortcutRecorder(
                title: "Built-in screen on or off", shortcut: $model.toggleBuiltinShortcut,
                defaultShortcut: .toggleBuiltin, other: model.reconnectAllShortcut,
                onRecording: model.pauseShortcuts)
        }
    }
}
