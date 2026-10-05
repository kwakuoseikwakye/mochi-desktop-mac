import AppKit
import MochiCore

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SpriteView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    weak var controller: PetController?
    private var mouseDownPoint: NSPoint?
    private var initialOrigin: NSPoint?
    private var moved = false

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        mouseDownPoint = NSEvent.mouseLocation
        initialOrigin = window?.frame.origin
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let origin = initialOrigin else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - start.x, dy = mouse.y - start.y
        guard moved || hypot(dx, dy) >= 3 else { return }
        if !moved { moved = true; controller?.beginDrag() }
        controller?.move(to: NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        if moved { controller?.endDrag() }
        else { controller?.click(count: event.clickCount) }
        mouseDownPoint = nil
        initialOrigin = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class PetController: NSObject {
    let panel: PetPanel
    private let sprite = SpriteView()
    private let manifest: Manifest
    private var images: [String: NSImage] = [:]
    private var companion = Companion()
    private var timer: Timer?
    private var previousTick = ProcessInfo.processInfo.systemUptime
    private var nextAmbient = ProcessInfo.processInfo.systemUptime + 5
    private var awareness = Awareness()
    private var nextSense = 0.0
    private var focus = Focus()
    private var roaming = Roaming()
    /// Exact x while walking. AppKit snaps window frames to whole points, so reading the frame
    /// back each tick loses the fraction and makes walks speed up leftward and slow down rightward.
    private var roamX: Double?
    private var renderedFrame: String?
    private let defaults: UserDefaults
    private let persistPreferences: Bool
    private var size: CGFloat

    init(defaults: UserDefaults = .standard, persistPreferences: Bool = true) throws {
        self.defaults = defaults
        self.persistPreferences = persistPreferences
        let resources = Bundle.module.resourceURL!.appendingPathComponent("Resources")
        let root = resources.appendingPathComponent("Sprites")
        manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json"))).validated()
        for clip in manifest.animations.values {
            for frame in clip.frames where images[frame] == nil {
                guard let image = NSImage(contentsOf: root.appendingPathComponent(frame)) else {
                    throw NSError(domain: "MochiAssets", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing sprite: \(frame)"])
                }
                images[frame] = image
            }
        }
        let storedSize = defaults.double(forKey: "petSize")
        size = [128.0, 192.0, 256.0].contains(storedSize) ? storedSize : 192
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Mochi"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = sprite
        sprite.controller = self
        sprite.setAccessibilityElement(true)
        sprite.setAccessibilityRole(.image)
        sprite.setAccessibilityLabel("Mochi desktop companion")
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let x = defaults.object(forKey: "petX") == nil ? screen.maxX - size - 32 : defaults.double(forKey: "petX")
        let y = defaults.object(forKey: "petY") == nil ? screen.minY + 24 : defaults.double(forKey: "petY")
        move(to: NSPoint(x: x.isFinite ? x : screen.minX, y: y.isFinite ? y : screen.minY))
        if defaults.bool(forKey: "sleeping") { companion.toggleSleep() }
        awareness.enabled = !defaults.bool(forKey: "awarenessOff")
        roaming.enabled = !defaults.bool(forKey: "roamingOff")
        let savedEnd = defaults.double(forKey: "focusEndsAt")
        focus.restore(endsAt: savedEnd > 0 ? Date(timeIntervalSince1970: savedEnd) : nil, now: Date())
        render()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
        save()
        panel.close()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        // Avoid replaying minutes of animation after system sleep or a blocked menu.
        let delta = min(max(now - previousTick, 0), 0.25)
        previousTick = now
        companion.advance(seconds: delta, clips: manifest.animations)
        if now >= nextAmbient {
            if companion.animation == "idle", !focus.isActive { companion.react(Bool.random() ? "blink" : "look") }
            nextAmbient = now + Double.random(in: 5...12)
        }
        if now >= nextSense {
            nextSense = now + 0.5
            if focus.update(now: Date()) { companion.react("heart"); save() }
            sense()
        }
        roam(delta: delta)
        render()
    }

    /// Mochi only wanders when it is resting near the bottom of its display and nothing else
    /// has a claim on it. Wherever the user has put it higher up, it stays put.
    private func roam(delta: Double) {
        guard let screen = panel.screen?.visibleFrame else { return }
        let frame = panel.frame
        let allowed = frame.minY - screen.minY <= 64
            && !companion.sleeping && !companion.dragging && !focus.isActive
            && awareness.activity != .typing
            && (companion.animation == "idle" || companion.walking)
        let room = Double(screen.minX)...Double(max(screen.minX, screen.maxX - frame.width))
        let x = roamX ?? Double(frame.minX)
        let out = roaming.update(dt: delta, canRoam: allowed, x: x, room: room)
        if out.dx != 0 {
            roamX = x + out.dx
            move(to: NSPoint(x: CGFloat(x + out.dx), y: frame.minY))
        }
        switch out.event {
        case .begin(let left): companion.startWalk(left: left)
        case .end: companion.stopWalk(); roamX = nil; save()
        case nil: break
        }
    }

    /// Reads only idle times and the frontmost app's bundle id: no key contents, no
    /// window titles, and no permission prompt.
    private func sense() {
        func idle(_ type: CGEventType) -> Double {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
        }
        let key = idle(.keyDown)
        let input = min(key, idle(.mouseMoved), idle(.scrollWheel), idle(.leftMouseDown))
        switch awareness.update(secondsSinceKey: key, secondsSinceInput: input,
                                frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                sleeping: companion.sleeping) {
        case .react(let name): if !focus.isActive { companion.react(name) }
        case .doze, .wake: companion.toggleSleep()
        case nil: break
        }
    }

    private func render() {
        guard let clip = manifest.animations[companion.animation] else { return }
        let frame = clip.frames[companion.frameIndex]
        guard renderedFrame != frame else { return }
        renderedFrame = frame
        sprite.image = images[frame]
        sprite.setAccessibilityValue(companion.animation)
    }

    func click(count: Int) {
        if companion.sleeping { companion.toggleSleep(); save() }
        else { companion.react(count >= 2 ? "heart" : Bool.random() ? "bounce" : "squish") }
        render()
    }

    func beginDrag() { companion.beginDrag(); render() }
    func endDrag() { companion.endDrag(); save(); render() }

    func move(to origin: NSPoint) {
        panel.setFrameOrigin(Placement.clamp(origin: origin, size: panel.frame.size,
                                            screens: NSScreen.screens.map(\.visibleFrame)))
    }

    private func save() {
        guard persistPreferences else { return }
        defaults.set(panel.frame.minX, forKey: "petX")
        defaults.set(panel.frame.minY, forKey: "petY")
        defaults.set(size, forKey: "petSize")
        defaults.set(companion.sleeping, forKey: "sleeping")
        defaults.set(!awareness.enabled, forKey: "awarenessOff")
        defaults.set(!roaming.enabled, forKey: "roamingOff")
        if let end = focus.endsAt { defaults.set(end.timeIntervalSince1970, forKey: "focusEndsAt") }
        else { defaults.removeObject(forKey: "focusEndsAt") }
    }

    @objc private func screensChanged() { move(to: panel.frame.origin); save() }
    @objc private func toggleSleep() { companion.toggleSleep(); save(); render() }
    @objc private func feed() { companion.react("eat"); render() }
    @objc private func heart() { companion.react("heart"); render() }
    @objc private func toggleAwareness() { awareness.enabled.toggle(); save() }
    @objc private func toggleRoaming() { roaming.enabled.toggle(); save() }
    @objc private func toggleFocus() {
        if focus.isActive { focus.stop() } else { focus.start(now: Date()) }
        save()
    }
    @objc private func resize(_ sender: NSMenuItem) {
        size = CGFloat(sender.tag)
        panel.setContentSize(NSSize(width: size, height: size))
        move(to: panel.frame.origin)
        save()
    }
    @objc private func bringBack() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        move(to: NSPoint(x: screen.maxX - size - 32, y: screen.minY + 24))
        panel.orderFrontRegardless()
        save()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Mochi")
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "Mochi · Mac preview", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        item("Show Mochi Here", action: #selector(bringBack), in: menu)
        item(companion.sleeping ? "Wake Up" : "Sleep", action: #selector(toggleSleep), in: menu)
        item("Feed", action: #selector(feed), in: menu).isEnabled = !companion.sleeping && !companion.dragging
        item("Heart", action: #selector(heart), in: menu).isEnabled = !companion.sleeping && !companion.dragging
        let minutesLeft = Int((focus.remaining(now: Date()) / 60).rounded(.up))
        item(focus.isActive ? "Stop Focus · \(minutesLeft) min left" : "Start Focus (\(Int(Focus.length / 60)) min)",
             action: #selector(toggleFocus), in: menu)
        item("Awareness", action: #selector(toggleAwareness), in: menu).state = awareness.enabled ? .on : .off
        item("Roaming", action: #selector(toggleRoaming), in: menu).state = roaming.enabled ? .on : .off
        let sizes = NSMenu(title: "Size")
        sizes.autoenablesItems = false
        for (name, pixels) in [("Small", 128), ("Medium", 192), ("Large", 256)] {
            let entry = item(name, action: #selector(resize(_:)), in: sizes)
            entry.tag = pixels
            entry.state = size == CGFloat(pixels) ? .on : .off
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Mochi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @discardableResult private func item(_ title: String, action: Selector, in menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    /// Exercises bundled images, rendering and panel construction without saving
    /// preferences or requiring global input permissions.
    func smokeCheck() throws {
        for clip in manifest.animations.values {
            for frame in clip.frames {
                sprite.image = images[frame]
                guard let bitmap = sprite.bitmapImageRepForCachingDisplay(in: sprite.bounds) else {
                    throw NSError(domain: "MochiSmoke", code: 1)
                }
                sprite.cacheDisplay(in: sprite.bounds, to: bitmap)
            }
        }
        print("Mochi smoke check passed: \(images.count) sprites, \(manifest.animations.count) animations, native panel rendered.")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var pet: PetController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let smoke = CommandLine.arguments.contains("--smoke-test")
            pet = try PetController(defaults: smoke ? UserDefaults(suiteName: "MochiSmoke-\(UUID())")! : .standard,
                                    persistPreferences: !smoke)
            if smoke {
                try pet?.smokeCheck()
                NSApp.terminate(nil)
                return
            }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "🌱"
            item.button?.toolTip = "Mochi desktop companion"
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } catch {
            if CommandLine.arguments.contains("--smoke-test") {
                fputs("Mochi smoke check failed: \(error)\n", stderr)
                exit(1)
            }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Mochi couldn’t start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let source = pet?.makeMenu() else { return }
        for item in source.items { source.removeItem(item); menu.addItem(item) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pet?.shutdown()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
