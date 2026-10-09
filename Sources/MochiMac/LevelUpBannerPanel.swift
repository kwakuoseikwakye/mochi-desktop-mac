import AppKit
import MochiCore

public final class LevelUpBannerPanel: NSPanel {
    private let pillView = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")

    public init() {
        let contentRect = NSRect(x: 0, y: 0, width: 220, height: 38)
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isReleasedWhenClosed = false

        pillView.frame = contentRect
        pillView.autoresizingMask = [.width, .height]
        pillView.material = .hudWindow
        pillView.blendingMode = .withinWindow
        pillView.state = .active
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = 14
        pillView.layer?.masksToBounds = true
        pillView.layer?.borderWidth = 1.0
        pillView.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        label.frame = NSRect(x: 12, y: 8, width: 196, height: 22)
        label.autoresizingMask = [.width]
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = .labelColor
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false

        pillView.addSubview(label)
        self.contentView = pillView
    }

    public func show(level: Int, phase: BondPhase, above frame: NSRect, completion: (() -> Void)? = nil) {
        let text = "🎉 Level \(level) · \(phase.displayName)"
        label.stringValue = text

        // Size to fit text comfortably
        let font = label.font ?? NSFont.systemFont(ofSize: 13, weight: .bold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let panelWidth = max(180, textWidth + 36)
        let panelHeight: CGFloat = 36

        let panelX = frame.midX - (panelWidth / 2)
        let startY = frame.maxY + 4
        let targetY = frame.maxY + 14

        label.frame = NSRect(x: 12, y: (panelHeight - 22) / 2, width: panelWidth - 24, height: 22)
        self.setFrame(NSRect(x: panelX, y: startY, width: panelWidth, height: panelHeight), display: true)
        self.alphaValue = 0.0
        self.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            self.animator().alphaValue = 1.0
            self.animator().setFrame(NSRect(x: panelX, y: targetY, width: panelWidth, height: panelHeight), display: true)
        }, completionHandler: { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self = self else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.5
                    self.animator().alphaValue = 0.0
                }, completionHandler: { [weak self] in
                    self?.close()
                    completion?()
                })
            }
        })
    }
}
