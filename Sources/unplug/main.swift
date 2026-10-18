import Foundation
import UnplugCore

let usage = """
usage: unplug <command> [options]

commands:
  list                         List displays, including ones Unplug disconnected
  disconnect <display>         Disconnect a display so macOS no longer sees it
  connect <display>            Reconnect a display Unplug disconnected
  connect --all                Reconnect every display Unplug disconnected
  toggle <display>             Disconnect if connected, otherwise reconnect
  forget <display>             Stop remembering a disconnected display that was
                               unplugged and can't be reconnected
  brightness <display> [0-100] Print a display's brightness, or set it in percent
  keyboard [on|off|toggle]     Turn the MacBook keyboard backlight on or off (no
                               argument prints its state)

<display> is an ID or UUID from `unplug list`, or part of the display's name.

options:
  --force                      Allow disconnecting the last active display
  --json                       (list) Print JSON instead of a table
  --version                    Print the version
"""

func warn(_ message: String) {
    FileHandle.standardError.write(Data("unplug: \(message)\n".utf8))
}

func fail(_ message: String) -> Never {
    warn(message)
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
let flags = Set(args.filter { $0.hasPrefix("--") })
let positional = args.filter { !$0.hasPrefix("--") }
let force = flags.contains("--force")
let manager = DisplayManager()

if flags.contains("--version") || positional.first == "version" {
    print("unplug \(UnplugVersion.current)")
    exit(0)
}

guard let command = positional.first else {
    print(usage)
    exit(flags.contains("--help") ? 0 : 1)
}

func target() -> Display {
    target(positional.dropFirst())
}

func target(_ words: ArraySlice<String>) -> Display {
    guard !words.isEmpty else { fail("\(command) needs a display. Run `unplug list`.") }
    do {
        return try manager.resolve(words.joined(separator: " "))
    } catch {
        fail(error.localizedDescription)
    }
}

func run(_ action: () throws -> Void, done: String) {
    do {
        try action()
        print(done)
    } catch {
        fail(error.localizedDescription)
    }
}

switch command {
case "list", "ls":
    let displays = manager.displays()
    if flags.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: (try? encoder.encode(displays)) ?? Data(), as: UTF8.self))
    } else if displays.isEmpty {
        print("No displays found.")
    } else {
        for d in displays {
            let state = d.isConnected ? "connected" : "disconnected"
            let kind = d.isBuiltin ? " (built-in)" : ""
            print("\(String(d.displayID).padding(toLength: 6, withPad: " ", startingAt: 0))"
                + "\(state.padding(toLength: 14, withPad: " ", startingAt: 0))"
                + "\(d.name)\(kind)  \(d.uuid)")
        }
    }

case "disconnect", "off":
    let d = target()
    run({ try manager.disconnect(d, force: force) }, done: "Disconnected \(d.name).")

case "connect", "on":
    if flags.contains("--all") {
        let failures = manager.connectAll()
        for (d, error) in failures {
            warn("\(d.name): \(error.localizedDescription)")
        }
        exit(failures.isEmpty ? 0 : 1)
    }
    let d = target()
    run({ try manager.connect(d) }, done: "Connected \(d.name).")

case "toggle":
    let d = target()
    run({ try manager.toggle(d, force: force) },
        done: d.isConnected ? "Disconnected \(d.name)." : "Connected \(d.name).")

case "forget":
    let d = target()
    guard !d.isConnected else { fail("\(d.name) is connected; only disconnected displays can be forgotten.") }
    manager.forget(d)
    print("Forgot \(d.name).")

case "brightness":
    // The last word is the new level when it's a number and a display is named before it.
    var words = positional.dropFirst()
    var level: Int?
    if words.count >= 2, let last = words.last, let value = Int(last.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) {
        guard (0...100).contains(value) else { fail("brightness must be between 0 and 100.") }
        level = value
        words = words.dropLast()
    }
    let d = target(words)
    let brightness = Brightness()
    if let level {
        guard brightness.set(d, Double(level) / 100) else { fail("\(d.name) doesn't support brightness control.") }
        print("\(d.name) brightness \(level)%.")
    } else {
        guard let current = brightness.get(d) else { fail("\(d.name) doesn't support brightness control.") }
        print("\(Int((current * 100).rounded()))%")
    }

case "keyboard", "kbd":
    guard KeyboardBacklight.isAvailable else { fail("this Mac has no keyboard backlight Unplug can control.") }
    switch positional.dropFirst().first {
    case nil:
        print(KeyboardBacklight.isOff ? "off" : "on")
    case "on"?:
        KeyboardBacklight.setOn(true)
        print("Keyboard backlight on.")
    case "off"?:
        KeyboardBacklight.setOn(false)
        print("Keyboard backlight off.")
    case "toggle"?:
        let on = KeyboardBacklight.isOff
        KeyboardBacklight.setOn(on)
        print(on ? "Keyboard backlight on." : "Keyboard backlight off.")
    case let other?:
        fail("unknown keyboard option \"\(other)\". Use on, off or toggle.")
    }

case "help":
    print(usage)

default:
    fail("unknown command \"\(command)\".\n\n\(usage)")
}
