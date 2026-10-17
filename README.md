# Unplug

Soft-disconnect a display on macOS so the system no longer sees it, and plug it back in with one click. Unplug is a menu bar app with a matching command line tool, free and open source under the MIT license.

It's useful for a Thunderbolt or USB-C monitor you want macOS to ignore without pulling the cable, for example to keep charging and the monitor's USB hub while the screen is off.

## How it works

Apple has no public API that disconnects a display. Unplug makes one private call, `CGSConfigureDisplayEnabled`, which is exported by CoreGraphics (from SkyLight). It is the same mechanism other display tools use. On Apple Silicon with macOS 13 or later, a disabled display is torn down completely: it disappears from the display list and stops using GPU resources.

Everything else uses Apple's documented [Quartz Display Services](https://developer.apple.com/documentation/coregraphics/quartz-display-services):

- Every change runs inside a display configuration transaction (`CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration`).
- Changes use session scope (`.forSession`), so logging out or restarting always brings every display back.
- The app listens for display changes with `CGDisplayRegisterReconfigurationCallback` instead of polling.
- Displays are tracked by UUID, because macOS can renumber display IDs.

A disconnected display drops out of every display list, so Unplug remembers the displays it disconnected in `~/Library/Application Support/Unplug/disconnected.json`. The app and the CLI share this file.

The private call lives in one file, [`Sources/UnplugCore/SkyLight.swift`](Sources/UnplugCore/SkyLight.swift), so it is easy to audit and to fix if Apple changes it. Because of it, Unplug can't ship on the Mac App Store.

### Keyboard backlight

When you disconnect a MacBook's built-in display, Unplug also turns the keyboard backlight off, and puts it back (including auto-brightness) when the display is reconnected. This uses the private `KeyboardBrightnessClient` class from CoreBrightness, isolated in [`KeyboardBacklight.swift`](Sources/UnplugCore/KeyboardBacklight.swift). Turn it off from the menu, or with:

```sh
defaults write io.github.mihaiflorinpopa.unplug keyboardBacklightFollowsBuiltin -bool false
```

### Safety

- Unplug refuses to disconnect the last active display unless you pass `--force`.
- By default, quitting the menu bar app reconnects every display it disconnected.
- If something goes wrong, log out and back in, or run `unplug connect --all`.

## Install

Download `Unplug-<version>.dmg` from [Releases](../../releases), open it, and drag Unplug into Applications.

Unplug isn't notarized by Apple yet, so the first launch is blocked. Right-click Unplug in Applications and choose Open, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Unplug.app
```

To use the command line tool, link it onto your PATH:

```sh
sudo ln -sf /Applications/Unplug.app/Contents/Helpers/unplug /usr/local/bin/unplug
```

### Build from source

```sh
./scripts/build-dmg.sh   # builds build/Unplug.app and build/Unplug-<version>.dmg
```

To publish a release, push a tag such as `v0.1.0`; CI builds the disk image and attaches it to a GitHub release.

## Command line

```sh
unplug list                    # displays, including ones Unplug disconnected
unplug disconnect "LG"         # by part of the name, display ID, or UUID
unplug connect "LG"
unplug toggle 3
unplug connect --all
unplug list --json
```

## Requirements

macOS 13 or later. Developed for Apple Silicon; Intel Macs are untested.

## Related projects

- [BetterDisplay](https://github.com/waydabber/BetterDisplay) and [Lunar](https://github.com/alin23/Lunar) both offer display disconnect, as closed-source or paid features.
- [blackoutd](https://github.com/toobuntu/blackoutd) uses the same call to turn off the built-in display automatically.
- [DisableMonitor](https://github.com/Eun/DisableMonitor) did this for older macOS versions and is archived.
