import AppKit
import UnplugCore

/// The menu bar menu: a real NSMenu, so items highlight, show checkmarks and
/// shortcuts as macOS draws them, with a brightness slider under each display as
/// a custom item view (NSMenuItem.view). SwiftUI's menu style can't hold a
/// slider. The menu is rebuilt each time it opens, with what's used often; every
/// option is in Settings.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let model: DisplaysModel
    private let updater: Updater
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var sliders: [String: BrightnessMenuView] = [:]

    init(model: DisplaysModel, updater: Updater) {
        self.model = model
        self.updater = updater
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "Unplug")
        statusItem.isVisible = model.showInMenuBar
        menu.delegate = self
        statusItem.menu = menu
        // So the first opening already has the sliders.
        model.refreshBrightness()
        watchBrightness()
    }

    var isVisible: Bool {
        get { statusItem.isVisible }
        set { statusItem.isVisible = newValue }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.menuOpened()
        rebuild()
    }


    private func rebuild() {
        menu.removeAllItems()
        sliders.removeAll()

        // Linked displays get their own section, with one slider for all of them.
        let linked = model.linkedDisplays
        let single = model.displays.filter { display in !linked.contains { $0.uuid == display.uuid } }
        if !single.isEmpty {
            menu.addItem(.sectionHeader(title: "Displays"))
        }
        for display in single {
            addDisplay(display)
            if display.isConnected, let level = model.brightness[display.uuid] {
                addSlider(for: display, level: level, name: display.name)
            }
            addForget(display)
        }
        if !linked.isEmpty {
            // The HIG separates groups of menu items with a separator.
            if !single.isEmpty { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: "Linked Displays"))
            for display in linked {
                addDisplay(display)
                addForget(display)
            }
            if let owner = sliderOwner(linked), let level = model.brightness[owner.uuid] {
                addSlider(for: owner, level: level, name: "Linked Displays")
            }
        }

        if model.keyboardBacklightAvailable {
            menu.addItem(.separator())
            add(Option.keyboardBacklight.title, #selector(toggleKeyboardBacklight)).state = model.keyboardLightOn ? .on : .off
        }

        if let error = model.lastError {
            menu.addItem(.separator())
            // No action, so the menu shows it disabled.
            menu.addItem(withTitle: error, action: nil, keyEquivalent: "")
        }

        if model.displays.contains(where: { !$0.isConnected }) {
            menu.addItem(.separator())
            add("Reconnect All Displays", #selector(reconnectAll))
        }

        menu.addItem(.separator())
        if updater.updateAvailable {
            add("Update Available…", #selector(checkForUpdates))
        }
        add("Settings…", #selector(openSettings), key: ",")
        add("About Unplug", #selector(about))
        add("Unplug Help", #selector(help))
        add("Quit Unplug", #selector(quit), key: "q")
    }

    private func addDisplay(_ display: Display) {
        add(display.name, #selector(toggleDisplay(_:)), represented: display.uuid).state = display.isConnected ? .on : .off
    }

    private func addForget(_ display: Display) {
        if model.unreachable.contains(display.uuid) {
            add("Forget \(display.name)", #selector(forget(_:)), represented: display.uuid)
        }
    }

    private func addSlider(for display: Display, level: Double, name: String) {
        let view = BrightnessMenuView(name: name, level: level) { [weak self] in
            self?.model.setBrightness(display, $0)
        }
        sliders[display.uuid] = view
        let row = NSMenuItem()
        row.view = view
        menu.addItem(row)
    }

    /// The linked display whose level the group's slider shows and sets: the
    /// first one that's on and has brightness control.
    private func sliderOwner(_ linked: [Display]) -> Display? {
        linked.first { $0.isConnected && model.brightness[$0.uuid] != nil }
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, key: String = "", represented: Any? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        item.representedObject = represented
        return item
    }

    /// Brightness is read in the background when the menu opens, so the sliders
    /// follow the levels as they arrive, and a display that turns out to support
    /// brightness gets its slider.
    private func watchBrightness() {
        withObservationTracking {
            _ = model.brightness
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let linked = self.model.linkedDisplays
                var owners = Set(self.model.displays
                    .filter { display in display.isConnected && self.model.brightness[display.uuid] != nil && !linked.contains { $0.uuid == display.uuid } }
                    .map(\.uuid))
                if let owner = self.sliderOwner(linked) { owners.insert(owner.uuid) }
                if owners != Set(self.sliders.keys) {
                    self.rebuild()
                } else {
                    for (uuid, view) in self.sliders {
                        if let level = self.model.brightness[uuid] { view.show(level) }
                    }
                }
                self.watchBrightness()
            }
        }
    }

    private func display(for item: NSMenuItem) -> Display? {
        model.displays.first { $0.uuid == item.representedObject as? String }
    }

    @objc private func toggleDisplay(_ item: NSMenuItem) {
        guard let display = display(for: item) else { return }
        model.setConnected(display, !display.isConnected)
    }

    @objc private func forget(_ item: NSMenuItem) {
        guard let display = display(for: item) else { return }
        model.forget(display)
    }

    @objc private func toggleKeyboardBacklight() {
        model.keyboardLightOn.toggle()
    }

    @objc private func reconnectAll() {
        model.connectAll()
    }

    @objc private func checkForUpdates() {
        NSApp.activate()
        updater.checkForUpdates()
    }

    /// SwiftUI's Settings scene adds the Settings… item to the app menu ("causes
    /// SwiftUI to enable the app's Settings menu item"). Choosing it is what ⌘,
    /// does; AppKit has no other public way to open a SwiftUI Settings scene.
    @objc private func openSettings() {
        NSApp.activate()
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," })
        else { return NSSound.beep() }
        appMenu.performActionForItem(at: index)
    }

    /// The standard About panel: icon, name, version, copyright and Credits.rtf.
    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    /// Opens the Help Book that Info.plist names.
    @objc private func help() {
        NSApp.showHelp(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// A brightness row for the menu, like macOS's own Display menu: a small sun, the
/// slider, a large sun, then the level in percent, as in Settings.
final class BrightnessMenuView: NSView {
    private let onChange: (Double) -> Void
    private let slider = MenuSlider()
    private let percent = NSTextField(labelWithString: "")
    /// True while this slider is being dragged, so readings don't move it.
    private var dragging = false

    /// `name` is what VoiceOver reads: the display's name, or Linked Displays.
    init(name: String, level: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        autoresizingMask = [.width]

        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.setAccessibilityLabel("\(name) brightness")
        percent.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        percent.textColor = .secondaryLabelColor
        percent.alignment = .right

        let stack = NSStackView(views: [sun("sun.min.fill"), slider, sun("sun.max.fill"), percent])
        stack.spacing = 6
        // Lines up with the item titles, past the checkmark column, and with the
        // shortcuts on the right. Menus have wider margins since macOS 26.
        if #available(macOS 26, *) {
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 29, bottom: 0, right: 17)
        } else {
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 22, bottom: 0, right: 14)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            percent.widthAnchor.constraint(equalToConstant: 40),
        ])
        show(level)
    }

    required init?(coder: NSCoder) { nil }

    /// Shows a level read from the display, unless the slider is being dragged.
    /// (Not the global mouse state: the click that opens the menu is still down
    /// while the menu fills in its sliders.)
    func show(_ level: Double) {
        guard !dragging else { return }
        slider.doubleValue = level
        percent.stringValue = "\(Int((level * 100).rounded()))%"
    }

    private func sun(_ name: String) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
        view.contentTintColor = .labelColor
        // Decorative: VoiceOver reads the slider's own label instead.
        view.setAccessibilityElement(false)
        return view
    }

    @objc private func changed() {
        // A continuous slider sends its last action on mouse up.
        dragging = NSApp.currentEvent?.type != .leftMouseUp
        percent.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%"
        onChange(slider.doubleValue)
    }
}

/// Draws the slider as macOS's Display menu does: a thin track filled in white
/// up to the level, and a white knob. A standard slider in a menu has no fill until it's
/// clicked, because AppKit draws it as in an inactive window.
private final class MenuSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 2.5, width: rect.width, height: 5)
        NSColor.systemFill.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
        var level = track
        level.size.width = knobRect(flipped: flipped).midX - track.minX
        NSColor.white.setFill()
        NSBezierPath(roundedRect: level, xRadius: 2.5, yRadius: 2.5).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let scale = (controlView as? MenuSlider)?.knobScale ?? 1
        guard scale > 0 else { return }
        let size = NSSize(width: 20 * scale, height: 16 * scale)
        let knob = NSRect(x: knobRect.midX - size.width / 2, y: knobRect.midY - size.height / 2,
                          width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 2
        shadow.shadowColor = .black.withAlphaComponent(0.3)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: knob, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// The slider, as in Control Center: the knob grows in while the pointer is over
/// the slider and shrinks away when it leaves.
private final class MenuSlider: NSSlider {
    /// 0 hides the knob, 1 shows it at full size.
    @objc dynamic var knobScale: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = MenuSliderCell()
        minValue = 0
        maxValue = 1
        // Always active: Unplug isn't the active app while its menu is open.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    /// Lets animator() animate the knob's size.
    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "knobScale" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    override func mouseEntered(with event: NSEvent) {
        showKnob(true)
    }

    override func mouseExited(with event: NSEvent) {
        // Keeps the knob while it's dragged past the slider's ends.
        if NSEvent.pressedMouseButtons == 0 { showKnob(false) }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // The drag is over: hide the knob if the pointer left the slider meanwhile.
        if let window, !bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            showKnob(false)
        }
    }

    private func showKnob(_ show: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            // Reduce Motion: the knob appears without growing in.
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
            animator().knobScale = show ? 1 : 0
        }
    }
}
