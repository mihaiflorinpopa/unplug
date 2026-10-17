<p align="center">
  <img src="Resources/icon/icon-1024.png" alt="Unplug app icon" width="160">
</p>

<h1 align="center">Unplug</h1>

<p align="center">Disconnect a display on your Mac without pulling the cable.</p>

Unplug makes macOS forget a display, as if you unplugged it, and brings it back with one click. The cable stays in, so the monitor can keep charging your laptop and powering its USB hub while its screen is off.

It's free, open source (MIT) and runs on macOS 13 or later.

## Install

1. Download `Unplug-<version>.dmg` from [Releases](../../releases/latest).
2. Open it and drag Unplug into Applications.
3. Open Unplug. macOS will warn that it can't check the app, because Unplug isn't notarized by Apple. Go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.

You only need step 3 once. After that, Unplug updates itself.

## Use it

Click the display icon in the menu bar:

- **Turn a display off or on** by clicking its name.
- **Brightness:** set each display's brightness, from the menu or with a slider in the window. Works for the built-in screen, Apple displays, and most other monitors (through DDC on Apple Silicon Macs).
- **Brightness keys:** turn on Options > "Brightness Keys for External Displays" and the keyboard's brightness keys work on whichever screen the pointer is on, with an on-screen indicator. macOS asks you to allow Unplug under Privacy & Security > Accessibility the first time.
- **Built-in screen:** on a MacBook you can also turn the keyboard backlight off, and have it go off with the screen.
- **Reconnect All Displays** brings everything back.
- **Options** has launch at login, keyboard shortcuts, and "Show in Dock" if you'd rather use Unplug as a regular app with a window.
- **Unplug Help** and **About Unplug** are at the bottom of the menu.

Keyboard shortcuts work anywhere:

| Shortcut | Does |
| --- | --- |
| ⌃⌥⌘U | Reconnect every display |
| ⌃⌥⌘B | Turn the built-in screen off or on |

## If something goes wrong

- Press **⌃⌥⌘U**, or quit Unplug. Quitting reconnects every display.
- Logging out or restarting always brings every display back.
- Unplug won't turn off your last working display.
- If you unplug a display while it's turned off in Unplug, choose **Forget** next to it in the menu.

## Command line

The `unplug` command comes inside the app. To use it from Terminal, link it once:

```sh
sudo ln -sf /Applications/Unplug.app/Contents/Helpers/unplug /usr/local/bin/unplug
```

Then:

```sh
unplug list                  # show displays
unplug disconnect "LG"       # by part of the name, ID or UUID
unplug connect "LG"
unplug toggle 3
unplug connect --all
unplug brightness "LG" 70    # set brightness in percent (leave out the number to read it)
unplug keyboard off          # keyboard backlight: on, off or toggle
unplug help                  # everything else
```

The command line and the app share their state, so you can turn a display off in one and back on in the other.

## How it works

Apple has no public way to disconnect a display. Unplug uses one private macOS call, `CGSConfigureDisplayEnabled`, the same one other display tools use. It lives in a single small file, [`SkyLight.swift`](Sources/UnplugCore/SkyLight.swift), so it's easy to check. Everything else uses Apple's documented [Quartz Display Services](https://developer.apple.com/documentation/coregraphics/quartz-display-services). Changes only last until you log out.

Unplug does nothing in the background. It wakes up only when macOS reports a display change, when you open the menu or press a shortcut, and to check for updates once a day.

The keyboard backlight uses another private call, from CoreBrightness, kept in [`KeyboardBacklight.swift`](Sources/UnplugCore/KeyboardBacklight.swift). Brightness uses Apple's private DisplayServices framework for the built-in screen and Apple displays, and the standard DDC/CI protocol for other monitors, all in [`Brightness.swift`](Sources/UnplugCore/Brightness.swift). Brightness is read only when you open the menu or the window.

## For developers

```sh
./scripts/build-dmg.sh   # builds build/Unplug.app and the .dmg
swift test               # runs the tests
```

To release, change the version in [`VERSION`](VERSION) and merge to main. CI publishes the GitHub release with the .dmg and the update feed (`appcast.xml`). Updates are checked with [Sparkle](https://sparkle-project.org) and signed with the key in the `SPARKLE_PRIVATE_KEY` repository secret. Its public half is [`Resources/sparkle-public-key.txt`](Resources/sparkle-public-key.txt).

## Author

Made by Mihai Florin Popa ([@mihaiflorinpopa](https://github.com/mihaiflorinpopa)).

## Related projects

- [BetterDisplay](https://github.com/waydabber/BetterDisplay) and [Lunar](https://github.com/alin23/Lunar) can also disconnect displays, as closed-source or paid features.
- [blackoutd](https://github.com/toobuntu/blackoutd) uses the same call to turn off the built-in screen automatically.
- [DisableMonitor](https://github.com/Eun/DisableMonitor) did this on older macOS and is archived.
