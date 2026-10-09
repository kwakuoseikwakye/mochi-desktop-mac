import AppKit
import AVFoundation
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

final class PetController: NSObject, NSMenuDelegate {
    let panel: PetPanel
    let soundManager: SoundManager
    private let bondManager: BondManager
    private var levelUpBanner: LevelUpBannerPanel?
    private var accumulatedTypingSeconds: Double = 0
    private let sprite = SpriteView()
    private let manifest: Manifest
    private var images: [String: NSImage] = [:]
    private var companion = Companion()
    private var cataloguePanel: EmoteCataloguePanel?
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
    private var lastEatFrame: Int = -1
    private let defaults: UserDefaults
    private let persistPreferences: Bool
    private var size: CGFloat

    init(defaults: UserDefaults = .standard, persistPreferences: Bool = true) throws {
        self.defaults = defaults
        self.persistPreferences = persistPreferences
        let isMuted = defaults.object(forKey: "soundMuted") != nil ? defaults.bool(forKey: "soundMuted") : true
        let volume = defaults.object(forKey: "soundVolume") != nil ? defaults.double(forKey: "soundVolume") : 0.5
        let focusRain = defaults.bool(forKey: "soundFocusRain")
        let soundSettings = SoundSettings(isMuted: isMuted, volume: volume, isFocusRainEnabled: focusRain)
        soundManager = SoundManager(settings: soundSettings, delegate: MacAudioService.shared)
        
        let storedBondLevel = defaults.integer(forKey: "bondLevel")
        let storedBondXP = defaults.integer(forKey: "bondCurrentXP")
        let storedDailyXP = defaults.integer(forKey: "bondDailyEarnedXP")
        let storedLastDate = defaults.string(forKey: "bondLastActiveDate") ?? ""
        let initialBondState = BondState(
            level: max(1, storedBondLevel),
            currentXP: max(0, storedBondXP),
            dailyEarnedXP: max(0, storedDailyXP),
            lastActiveDate: storedLastDate
        )
        self.bondManager = BondManager(state: initialBondState)

        let resources = Bundle.module.resourceURL!.appendingPathComponent("Resources")
        let root = resources.appendingPathComponent("Sprites")
        manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json"))).validated()
        companion = Companion(manifest: manifest)
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
        self.bondManager.onLevelUp = { [weak self] level, phase in
            self?.celebrateLevelUp(level: level, phase: phase)
        }
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
        if focus.isActive {
            soundManager.startFocusAmbience()
        }
        render()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func shutdown() {
        soundManager.stopFocusAmbience()
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
        cataloguePanel?.close()
        cataloguePanel = nil
        save()
        panel.close()
    }

    private func celebrateLevelUp(level: Int, phase: BondPhase) {
        companion.react("sparkle")
        soundManager.trigger(.levelUp)
        if levelUpBanner == nil {
            levelUpBanner = LevelUpBannerPanel()
        }
        levelUpBanner?.show(level: level, phase: phase, above: panel.frame)
        save()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        // Avoid replaying minutes of animation after system sleep or a blocked menu.
        let delta = min(max(now - previousTick, 0), 0.25)
        previousTick = now
        companion.tick(now: now, elapsed: delta)
        if companion.animation == "eat" {
            if companion.frameIndex >= 2 && lastEatFrame < 2 {
                soundManager.trigger(.eat)
            }
            lastEatFrame = companion.frameIndex
        } else {
            lastEatFrame = -1
        }
        if now >= nextAmbient {
            if companion.animation == "idle", !focus.isActive { companion.react(Bool.random() ? "blink" : "look") }
            nextAmbient = now + Double.random(in: 5...12)
        }
        if now >= nextSense {
            nextSense = now + 0.5
            if focus.update(now: Date()) {
                companion.react("heart")
                soundManager.stopFocusAmbience()
                soundManager.trigger(.levelUp)
                bondManager.recordFocusCompleted(at: Date())
                save()
            }
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
        
        if awareness.activity == .typing {
            accumulatedTypingSeconds += 0.5
            if accumulatedTypingSeconds >= 1.0 {
                bondManager.recordTyping(seconds: accumulatedTypingSeconds, at: Date())
                accumulatedTypingSeconds = 0
            }
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
        else {
            let reaction = count >= 2 ? "heart" : Bool.random() ? "bounce" : "squish"
            companion.react(reaction)
            if reaction == "bounce" || reaction == "squish" {
                soundManager.trigger(.chirp)
            }
        }
        render()
    }

    func beginDrag() { companion.beginDrag(); render() }
    func endDrag() { companion.endDrag(); save(); render() }

    func playEmote(_ emote: Emote) {
        let wasSleeping = companion.sleeping
        companion.playEmote(emote, now: ProcessInfo.processInfo.systemUptime)
        if wasSleeping { save() }
        render()
    }

    @objc func showEmoteCatalogue() {
        if cataloguePanel == nil {
            cataloguePanel = EmoteCataloguePanel(
                frameProvider: { [weak self] emote in
                    guard let self = self, let clip = self.manifest.animations[emote.id] else { return [] }
                    return clip.frames.compactMap { self.images[$0] }
                },
                onSelect: { [weak self] emote in
                    self?.playEmote(emote)
                }
            )
            cataloguePanel?.center()
        }
        cataloguePanel?.orderFrontRegardless()
        cataloguePanel?.makeKey()
        cataloguePanel?.focusSearch()
        NSApp.activate(ignoringOtherApps: true)
    }

    func move(to origin: NSPoint) {
        panel.setFrameOrigin(Placement.clamp(origin: origin, size: panel.frame.size,
                                            screens: NSScreen.screens.map(\.visibleFrame)))
    }

    func saveSoundSettings() {
        guard persistPreferences else { return }
        defaults.set(soundManager.settings.isMuted, forKey: "soundMuted")
        defaults.set(soundManager.settings.volume, forKey: "soundVolume")
        defaults.set(soundManager.settings.isFocusRainEnabled, forKey: "soundFocusRain")
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
        defaults.set(bondManager.state.level, forKey: "bondLevel")
        defaults.set(bondManager.state.currentXP, forKey: "bondCurrentXP")
        defaults.set(bondManager.state.dailyEarnedXP, forKey: "bondDailyEarnedXP")
        defaults.set(bondManager.state.lastActiveDate, forKey: "bondLastActiveDate")
        saveSoundSettings()
    }

    @objc private func screensChanged() { move(to: panel.frame.origin); save() }
    @objc private func toggleSleep() { companion.toggleSleep(); save(); render() }
    @objc private func feed() { 
        companion.react("eat")
        render()
        bondManager.recordFeeding(at: Date())
        save()
    }
    @objc private func heart() { companion.react("heart"); render() }
    @objc private func toggleAwareness() { awareness.enabled.toggle(); save() }
    @objc private func toggleRoaming() { roaming.enabled.toggle(); save() }

    func startFocusSession() {
        focus.start(now: Date())
        soundManager.startFocusAmbience()
        save()
    }

    func endFocusSession() {
        focus.stop()
        soundManager.stopFocusAmbience()
        soundManager.trigger(.levelUp)
        save()
    }

    func cancelFocusSession() {
        endFocusSession()
    }

    @objc private func toggleFocus() {
        if focus.isActive { endFocusSession() } else { startFocusSession() }
    }

    func setVolume(_ newVolume: Double) {
        var settings = soundManager.settings
        settings.setVolume(newVolume)
        soundManager.updateSettings(settings)
        saveSoundSettings()
        if focus.isActive && soundManager.settings.isFocusRainEnabled && !soundManager.settings.isMuted {
            soundManager.startFocusAmbience()
        }
    }

    @objc func selectVolume(_ sender: NSMenuItem) {
        let percent = sender.tag > 0 ? sender.tag : 50
        setVolume(Double(percent) / 100.0)
    }

    @objc func selectVolume() {
        setVolume(0.5)
    }

    @objc func toggleSoundMuted() {
        var settings = soundManager.settings
        settings.isMuted.toggle()
        soundManager.updateSettings(settings)
        saveSoundSettings()
        if !settings.isMuted && focus.isActive && settings.isFocusRainEnabled {
            soundManager.startFocusAmbience()
        }
    }

    @objc func toggleFocusRain() {
        var settings = soundManager.settings
        settings.isFocusRainEnabled.toggle()
        soundManager.updateSettings(settings)
        saveSoundSettings()
        if focus.isActive {
            if settings.isFocusRainEnabled {
                soundManager.startFocusAmbience()
            } else {
                soundManager.stopFocusAmbience()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        soundManager.trigger(.menuOpen)
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
        menu.delegate = self
        let title = NSMenuItem(title: "Mochi · Mac preview", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        
        let bond = bondManager.state
        let bondTitle = "🌱 Level \(bond.level) · \(bond.phase.displayName) (\(bond.currentXP)/\(bond.xpNeededForNextLevel) XP)"
        let bondItem = NSMenuItem(title: bondTitle, action: nil, keyEquivalent: "")
        bondItem.isEnabled = false
        menu.addItem(bondItem)
        
        menu.addItem(.separator())
        item("Show Mochi Here", action: #selector(bringBack), in: menu)
        item(companion.sleeping ? "Wake Up" : "Sleep", action: #selector(toggleSleep), in: menu)
        item("Feed", action: #selector(feed), in: menu).isEnabled = !companion.sleeping && !companion.dragging
        item("Heart", action: #selector(heart), in: menu).isEnabled = !companion.sleeping && !companion.dragging
        item("Emote Catalogue...", action: #selector(showEmoteCatalogue), in: menu).isEnabled = !companion.dragging
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
        let soundTitle = soundManager.settings.isMuted ? "Sound Effects: Off" : "Sound Effects: On"
        let soundItem = item(soundTitle, action: #selector(toggleSoundMuted), in: menu)
        soundItem.state = soundManager.settings.isMuted ? .off : .on

        let volumes = NSMenu(title: "Volume")
        volumes.autoenablesItems = false
        for (name, percent) in [("25%", 25), ("50%", 50), ("75%", 75), ("100%", 100)] {
            let entry = item(name, action: #selector(selectVolume(_:)), in: volumes)
            entry.tag = percent
            let targetVol = Double(percent) / 100.0
            entry.state = abs(soundManager.settings.volume - targetVol) < 0.01 ? .on : .off
        }
        let volumeItem = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volumeItem.submenu = volumes
        menu.addItem(volumeItem)

        let rainTitle = soundManager.settings.isFocusRainEnabled ? "Focus Rain Ambience: On" : "Focus Rain Ambience: Off"
        let rainItem = item(rainTitle, action: #selector(toggleFocusRain), in: menu)
        rainItem.state = soundManager.settings.isFocusRainEnabled ? .on : .off
        menu.addItem(.separator())
        item("Reset Bond...", action: #selector(confirmResetBond), in: menu)
        let quit = NSMenuItem(title: "Quit Mochi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc func confirmResetBond() {
        let alert = NSAlert()
        alert.messageText = "Reset Bond Progression?"
        alert.informativeText = "This will return Mochi's relationship to Level 1 and 0 XP. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset Bond")
        if alert.runModal() == .alertSecondButtonReturn {
            bondManager.reset()
            save()
        }
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
        for emote in EmoteCatalog.all {
            guard manifest.animations[emote.id] != nil else {
                throw NSError(domain: "MochiSmoke", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Missing emote animation: \(emote.id)"])
            }
        }
        for clip in manifest.animations.values {
            for frame in clip.frames {
                sprite.image = images[frame]
                guard let bitmap = sprite.bitmapImageRepForCachingDisplay(in: sprite.bounds) else {
                    throw NSError(domain: "MochiSmoke", code: 1)
                }
                sprite.cacheDisplay(in: sprite.bounds, to: bitmap)
            }
        }
        var selectedEmote: Emote?
        let testPanel = EmoteCataloguePanel(
            frameProvider: { [weak self] emote in
                guard let self = self, let clip = self.manifest.animations[emote.id] else { return [] }
                return clip.frames.compactMap { self.images[$0] }
            },
            onSelect: { emote in
                selectedEmote = emote
            }
        )
        guard testPanel.gridView.cardViews.count == EmoteCatalog.all.count else {
            throw NSError(domain: "MochiSmoke", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected all emotes in catalogue panel"])
        }
        guard testPanel.gridView.emptyLabel.isHidden else {
            throw NSError(domain: "MochiSmoke", code: 4, userInfo: [NSLocalizedDescriptionKey: "Empty label should be hidden initially"])
        }
        // Test query filtering
        testPanel.searchField.stringValue = "coffee"
        testPanel.reloadGrid()
        guard testPanel.gridView.cardViews.count == 1, testPanel.gridView.cardViews.first?.emote.id == "coffee" else {
            throw NSError(domain: "MochiSmoke", code: 5, userInfo: [NSLocalizedDescriptionKey: "Search query filtering failed"])
        }
        // Test empty state
        testPanel.searchField.stringValue = "xyz_nonexistent_emote"
        testPanel.reloadGrid()
        guard testPanel.gridView.cardViews.isEmpty, !testPanel.gridView.emptyLabel.isHidden else {
            throw NSError(domain: "MochiSmoke", code: 6, userInfo: [NSLocalizedDescriptionKey: "Empty state failed"])
        }
        // Test category filtering
        testPanel.searchField.stringValue = ""
        testPanel.segmentedControl.selectedSegment = 2 // Work
        testPanel.reloadGrid()
        let expectedWorkCount = EmoteCatalog.search(query: "", category: .work).count
        guard testPanel.gridView.cardViews.count == expectedWorkCount else {
            throw NSError(domain: "MochiSmoke", code: 7, userInfo: [NSLocalizedDescriptionKey: "Category filtering failed"])
        }
        // Test selection callback
        testPanel.gridView.cardViews.first?.onSelect(testPanel.gridView.cardViews.first!.emote)
        guard selectedEmote != nil else {
            throw NSError(domain: "MochiSmoke", code: 8, userInfo: [NSLocalizedDescriptionKey: "Emote card selection failed"])
        }
        // Test pet playEmote and tick duration expiration
        let testEmote = EmoteCatalog.all[0]
        playEmote(testEmote)
        guard companion.animation == testEmote.id, companion.activeEmote == testEmote else {
            throw NSError(domain: "MochiSmoke", code: 9, userInfo: [NSLocalizedDescriptionKey: "playEmote did not set animation"])
        }
        let now = ProcessInfo.processInfo.systemUptime + testEmote.playbackDuration + 1
        companion.tick(now: now, elapsed: 0.1)
        guard companion.animation == "idle", companion.activeEmote == nil else {
            throw NSError(domain: "MochiSmoke", code: 10, userInfo: [NSLocalizedDescriptionKey: "companion.tick did not expire emote"])
        }
        testPanel.orderFrontRegardless()
        testPanel.close()

        // Test sound settings defaults and controls
        guard soundManager.settings.isMuted == true else {
            throw NSError(domain: "MochiSmoke", code: 11, userInfo: [NSLocalizedDescriptionKey: "Default isMuted should be true"])
        }
        guard abs(soundManager.settings.volume - 0.5) < 0.001 else {
            throw NSError(domain: "MochiSmoke", code: 12, userInfo: [NSLocalizedDescriptionKey: "Default volume should be 0.5"])
        }
        guard soundManager.settings.isFocusRainEnabled == false else {
            throw NSError(domain: "MochiSmoke", code: 13, userInfo: [NSLocalizedDescriptionKey: "Default isFocusRainEnabled should be false"])
        }
        toggleSoundMuted()
        guard soundManager.settings.isMuted == false else {
            throw NSError(domain: "MochiSmoke", code: 14, userInfo: [NSLocalizedDescriptionKey: "toggleSoundMuted failed"])
        }
        let testVolumeItem = NSMenuItem(title: "75%", action: #selector(selectVolume(_:)), keyEquivalent: "")
        testVolumeItem.tag = 75
        selectVolume(testVolumeItem)
        guard abs(soundManager.settings.volume - 0.75) < 0.001 else {
            throw NSError(domain: "MochiSmoke", code: 15, userInfo: [NSLocalizedDescriptionKey: "selectVolume failed"])
        }
        toggleFocusRain()
        guard soundManager.settings.isFocusRainEnabled == true else {
            throw NSError(domain: "MochiSmoke", code: 16, userInfo: [NSLocalizedDescriptionKey: "toggleFocusRain failed"])
        }
        let smokeMenu = makeMenu()
        guard smokeMenu.items.contains(where: { $0.title.contains("Sound Effects") }),
              smokeMenu.items.contains(where: { $0.title == "Volume" }),
              smokeMenu.items.contains(where: { $0.title.contains("Focus Rain Ambience") }) else {
            throw NSError(domain: "MochiSmoke", code: 17, userInfo: [NSLocalizedDescriptionKey: "Menu missing sound controls"])
        }
        // Test focus session start and end
        startFocusSession()
        guard focus.isActive else {
            throw NSError(domain: "MochiSmoke", code: 18, userInfo: [NSLocalizedDescriptionKey: "startFocusSession failed"])
        }
        endFocusSession()
        guard !focus.isActive else {
            throw NSError(domain: "MochiSmoke", code: 19, userInfo: [NSLocalizedDescriptionKey: "endFocusSession failed"])
        }
        // Test click chirp
        click(count: 1)
        // Test menu open trigger
        menuWillOpen(smokeMenu)
        // Restore muted
        toggleSoundMuted()
        toggleFocusRain()

        // Verify audio assets in Resources/Audio
        let resources = Bundle.module.resourceURL?.appendingPathComponent("Resources")
        var audioDir = resources?.appendingPathComponent("Audio")
        if let dir = audioDir, !FileManager.default.fileExists(atPath: dir.path) {
            if FileManager.default.fileExists(atPath: "macos/Sources/MochiMac/Resources/Audio") {
                audioDir = URL(fileURLWithPath: "macos/Sources/MochiMac/Resources/Audio")
            } else if FileManager.default.fileExists(atPath: "Sources/MochiMac/Resources/Audio") {
                audioDir = URL(fileURLWithPath: "Sources/MochiMac/Resources/Audio")
            }
        }
        guard let validAudioDir = audioDir, FileManager.default.fileExists(atPath: validAudioDir.path) else {
            throw NSError(domain: "MochiSmoke", code: 20, userInfo: [NSLocalizedDescriptionKey: "Resources/Audio directory missing"])
        }
        let expectedAudioFiles = ["chirp.wav", "eat.wav", "spawn.wav", "exit.wav", "menu_open.wav", "level_up.wav", "rain.wav"]
        for filename in expectedAudioFiles {
            let fileURL = validAudioDir.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw NSError(domain: "MochiSmoke", code: 21, userInfo: [NSLocalizedDescriptionKey: "Missing audio asset: \(filename)"])
            }
            let player = try AVAudioPlayer(contentsOf: fileURL)
            guard player.duration > 0.0 else {
                throw NSError(domain: "MochiSmoke", code: 22, userInfo: [NSLocalizedDescriptionKey: "Audio asset \(filename) duration <= 0: \(player.duration)"])
            }
        }

        print("[Smoke Test] Verified \(images.count) sprites across \(manifest.animations.count) animations.")
        print("[Smoke Test] Verified \(expectedAudioFiles.count) audio assets with valid durations.")
        print("[Smoke Test] PASSED")
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
                // Verify Bond Progression system
                let testBond = BondManager(state: BondState(level: 1, currentXP: 0, dailyEarnedXP: 0, lastActiveDate: "2026-10-09"))
                let earned = testBond.recordTyping(seconds: 500, at: Date())
                guard earned == 480 || earned == 500 else {
                    fputs("Smoke test failed: bond XP calculation unexpected\n", stderr)
                    exit(1)
                }
                let bannerTest = LevelUpBannerPanel()
                guard bannerTest.level == .floating else {
                    fputs("Smoke test failed: LevelUpBannerPanel level is not floating\n", stderr)
                    exit(1)
                }
                try pet?.smokeCheck()
                NSApp.terminate(nil)
                return
            }
            pet?.soundManager.trigger(.spawn)
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

    func menuWillOpen(_ menu: NSMenu) {
        pet?.soundManager.trigger(.menuOpen)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let source = pet?.makeMenu() else { return }
        for item in source.items { source.removeItem(item); menu.addItem(item) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pet?.soundManager.trigger(.exit)
        pet?.shutdown()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
