import AppKit
import MochiCore

final class EmoteCardView: NSView {
    let emote: Emote
    let onSelect: (Emote) -> Void

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var hoverTimer: Timer?
    private var currentFrameIndex = 0
    private let frames: [NSImage]

    init(emote: Emote, frames: [NSImage], onSelect: @escaping (Emote) -> Void) {
        self.emote = emote
        self.frames = frames
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 110))
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor

        imageView.wantsLayer = true
        imageView.layer?.magnificationFilter = .nearest
        imageView.layer?.minificationFilter = .nearest
        imageView.frame = NSRect(x: 18, y: 34, width: 64, height: 64)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = frames.first
        addSubview(imageView)

        titleLabel.frame = NSRect(x: 4, y: 6, width: 92, height: 24)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.stringValue = emote.displayName
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        addSubview(titleLabel)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        guard frames.count > 1 else { return }
        hoverTimer?.invalidate()
        currentFrameIndex = 0
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, !self.frames.isEmpty else { return }
            self.currentFrameIndex = (self.currentFrameIndex + 1) % self.frames.count
            self.imageView.image = self.frames[self.currentFrameIndex]
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        stopHoverAnimation()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect(emote)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
            stopHoverAnimation()
        }
    }

    private func stopHoverAnimation() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        currentFrameIndex = 0
        imageView.image = frames.first
    }

    deinit {
        hoverTimer?.invalidate()
    }
}
