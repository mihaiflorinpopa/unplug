# Unplug: notes for coding agents

Unplug is a macOS menu bar app, with an `unplug` CLI inside it, that makes macOS forget a display without pulling the cable, and sets display and keyboard backlight brightness. The README describes what it does.

## Build and test

- `swift test` runs the UnplugCore tests.
- `./scripts/build-app.sh` builds `build/Unplug.app` (universal, ad-hoc signed). `./scripts/build-dmg.sh` also makes the .dmg.
- To try a build, quit the installed Unplug first (two copies both react to displays and shortcuts), then `open build/Unplug.app`.
- Logs: `/usr/bin/log show --last 10m --predicate 'subsystem == "io.github.mihaiflorinpopa.unplug"'`. In zsh, plain `log` is a shell builtin. Debug lines, such as menu opens, only show in `log stream --level debug`.
- Universal builds made with Xcode 27 (Swift 6.4) record `sdk 14.0`, the deployment target. CI (Xcode 26) records the real SDK and checks it.

## Layout

- `Sources/UnplugCore`: displays (`DisplayManager`, `DisplayMonitor`, `SkyLight`), brightness (`Brightness`: DisplayServices for the built-in screen, Apple displays and HDR monitors, DDC/CI for other monitors), `KeyboardBacklight`, `UnplugSettings` (shared with the CLI), `BuiltinFollower`. Tests are in `Tests/UnplugCoreTests`.
- `Sources/UnplugApp`: the menu bar app. `StatusMenu` (AppKit menu with slider rows), `DisplaysModel` (`@Observable`), the SwiftUI `Settings` scene, the Dock window, Sparkle (`Updater`), shortcuts (Carbon `RegisterEventHotKey`, which needs no Accessibility permission).
- `Sources/unplug`: the CLI, bundled at `Unplug.app/Contents/Helpers/unplug`.
- `Resources/`: Info.plist, privacy manifest, Help Book, icon (Icon Composer `Unplug.icon`, plus `icon-1024.png` for macOS 14 and 15).

## Rules

- Follow the upstream documentation of every component, for the version the project uses: Apple's (AppKit, SwiftUI, Observation, CoreGraphics, ServiceManagement, Carbon, the HIG, App Review Guidelines), Sparkle's, SwiftPM's and GitHub Actions'. Read it before changing how a component is used, quote it in the pull request, and say plainly when something is a workaround the docs don't describe. Apple's pages are rendered with JavaScript, so fetch their JSON: `https://developer.apple.com/tutorials/data/documentation/<path>.json`, and `…/tutorials/data/design/human-interface-guidelines/<page>.json` for the HIG. The SDK headers (`xcrun --show-sdk-path`) settle availability and deprecation.
- Event-driven only: no repeating timers, polling or background loops. Changes come from `CGDisplayRegisterReconfigurationCallback`, wake notifications and the menu opening. Brightness is read only when the menu or a window opens.
- Use Apple's documented APIs and follow the HIG wherever they cover it. Private APIs are only for what has no public API (turning a display off, Apple Silicon and DDC brightness, the keyboard backlight), and stay in `SkyLight.swift`, `Brightness.swift` and `KeyboardBacklight.swift`. Display changes use the `.forSession` scope.
- Swift 6 language mode. A `DisplaysModel` property stored elsewhere (UserDefaults, CoreBrightness, SMAppService) must call `access(keyPath:)` and `withMutation(keyPath:)`, or its UI goes stale.
- Keep the app lightweight, the design minimal and the README easy to read. Keep the app icon's artwork.
- Sign from the inside out. Never use `codesign --deep`.
- Third-party code shipped in the app keeps its license notice in the app: `build-app.sh` copies Sparkle's `LICENSE` to `Contents/Resources/Sparkle LICENSE.txt`, and CI checks it.
- Never weaken or delete tests or assertions to make a check pass.
- Feature work goes through a pull request, and CI must pass before merging. A ruleset on `main` enforces both and blocks force pushes.
- Commits and pull requests carry no AI-tool attribution: no Co-Authored-By trailers, no "Generated with" lines.

## Releases

- Bump `VERSION` and merge to main. CI builds the .dmg, signs it and `appcast.xml` (Sparkle EdDSA, the `SPARKLE_PRIVATE_KEY` secret) and publishes the GitHub release. Merges that don't change `VERSION` don't release.
- The build number is the commit count.
- Releases are immutable: once published, a release's assets and tag can't change. Fix a broken release with a new `VERSION`.
- CI runs on a pinned `macos-26` runner (bump it by hand when GitHub retires it). Actions are pinned to commit SHAs, and Dependabot updates them and Sparkle.

## Already decided

Ask the maintainer before revisiting these.

- The private APIs stay. That rules out the Mac App Store (guideline 2.5.1, and its sandbox).
- The menu is AppKit, not SwiftUI's `MenuBarExtra`: SwiftUI menus can't hold sliders, and the SwiftUI panel didn't look native. Displays use checkmarks, not switches (the HIG keeps switches to list rows). The sliders are drawn like macOS's own Display menu (`NSSliderCell` `drawBar`/`drawKnob`), because a standard slider in a menu shows no fill until it's clicked.
- No Control Center controls or App Intents for now: without a Developer ID team, macOS rejects the extension's intents. No Xcode project until then.
- Developer ID signing, notarization and Homebrew wait for the maintainer.
- The brightness keys were removed: they needed the Accessibility permission and didn't work on some monitors.
- A monitor changed with its own buttons doesn't move linked displays, since that would need polling.
- English only.

## Not verified

macOS 14, 15 and 26 (the menu's slider margins are 22/14 points before macOS 26 and 29/17 from it), Intel Macs, and virtual "dummy" displays. Unplugging the dock with the lid closed was tested and works: the Mac sleeps, and the built-in screen comes back when the lid opens.
