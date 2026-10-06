import AppKit
import MochiCore

final class EmoteGridView: NSView {
    override var isFlipped: Bool { true }

    let emptyLabel = NSTextField(labelWithString: "No emotes found")
    private(set) var cardViews: [EmoteCardView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        emptyLabel.alignment = .center
        emptyLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isEditable = false
        emptyLabel.isSelectable = false
        emptyLabel.isBordered = false
        emptyLabel.drawsBackground = false
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
    }

    func update(cards: [EmoteCardView]) {
        for card in cardViews {
            card.removeFromSuperview()
        }
        cardViews = cards
        for card in cardViews {
            addSubview(card)
        }
        emptyLabel.isHidden = !cards.isEmpty
        recalculateLayout()
    }

    func recalculateLayout() {
        let scrollWidth = enclosingScrollView?.contentSize.width ?? bounds.width
        let availableWidth = scrollWidth > 0 ? scrollWidth : (bounds.width > 0 ? bounds.width : 480)
        let scrollHeight = enclosingScrollView?.contentSize.height ?? bounds.height
        let visibleHeight = scrollHeight > 0 ? scrollHeight : (bounds.height > 0 ? bounds.height : 300)

        let cardWidth: CGFloat = 100
        let cardHeight: CGFloat = 110
        let spacing: CGFloat = 12
        let margin: CGFloat = 16

        let usableWidth = max(availableWidth - (margin * 2), cardWidth)
        let columns = max(1, Int((usableWidth + spacing) / (cardWidth + spacing)))
        let totalGridWidth = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing
        let startX = max(margin, (availableWidth - totalGridWidth) / 2)

        for (i, card) in cardViews.enumerated() {
            let col = i % columns
            let row = i / columns
            let x = startX + CGFloat(col) * (cardWidth + spacing)
            let y = margin + CGFloat(row) * (cardHeight + spacing)
            card.frame = NSRect(x: x, y: y, width: cardWidth, height: cardHeight)
        }

        let rowCount = (cardViews.count + columns - 1) / columns
        let totalContentHeight = rowCount > 0
            ? margin + CGFloat(rowCount) * (cardHeight + spacing) - spacing + margin
            : 0

        let targetHeight = max(totalContentHeight, visibleHeight)
        let targetFrame = NSRect(x: 0, y: 0, width: availableWidth, height: targetHeight)
        if frame != targetFrame {
            frame = targetFrame
        }

        if cardViews.isEmpty {
            emptyLabel.frame = NSRect(x: 16, y: max(0, (visibleHeight - 30) / 2), width: max(availableWidth - 32, 100), height: 30)
        }
    }
}

final class EmoteCataloguePanel: NSPanel, NSWindowDelegate, NSSearchFieldDelegate {
    private let frameProvider: (Emote) -> [NSImage]
    private let onSelect: (Emote) -> Void
    private var cardCache: [String: EmoteCardView] = [:]

    let searchField = NSSearchField()
    let segmentedControl = NSSegmentedControl()
    let scrollView = NSScrollView()
    let gridView = EmoteGridView()
    private var clipViewObserver: NSObjectProtocol?

    init(frameProvider: @escaping (Emote) -> [NSImage], onSelect: @escaping (Emote) -> Void) {
        self.frameProvider = frameProvider
        self.onSelect = onSelect

        let defaultRect = NSRect(x: 0, y: 0, width: 480, height: 420)
        super.init(
            contentRect: defaultRect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Emote Catalogue"
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 360, height: 300)
        isOpaque = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        appearance = NSAppearance(named: .vibrantDark)
        delegate = self

        setupUI()
        reloadGrid()
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    private func setupUI() {
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        contentView = visualEffect

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search emotes..."
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchAction(_:))
        visualEffect.addSubview(searchField)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.segmentCount = EmoteCategory.allCases.count
        for (i, cat) in EmoteCategory.allCases.enumerated() {
            segmentedControl.setLabel(cat.rawValue, forSegment: i)
        }
        segmentedControl.selectedSegment = 0
        segmentedControl.segmentDistribution = .fillEqually
        segmentedControl.trackingMode = .selectOne
        segmentedControl.target = self
        segmentedControl.action = #selector(categoryChanged(_:))
        visualEffect.addSubview(segmentedControl)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = gridView
        visualEffect.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: visualEffect.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),

            segmentedControl.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

        scrollView.contentView.postsFrameChangedNotifications = true
        clipViewObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.gridView.recalculateLayout()
        }
    }

    @objc private func searchAction(_ sender: Any?) {
        reloadGrid()
    }

    @objc private func categoryChanged(_ sender: Any?) {
        reloadGrid()
    }

    func controlTextDidChange(_ obj: Notification) {
        reloadGrid()
    }

    func reloadGrid() {
        let query = searchField.stringValue
        let index = segmentedControl.selectedSegment
        let category = (index >= 0 && index < EmoteCategory.allCases.count)
            ? EmoteCategory.allCases[index]
            : .all

        let filtered = EmoteCatalog.search(query: query, category: category)
        let cards = filtered.map { emote -> EmoteCardView in
            if let cached = cardCache[emote.id] {
                return cached
            }
            let frames = frameProvider(emote)
            let card = EmoteCardView(emote: emote, frames: frames, onSelect: onSelect)
            cardCache[emote.id] = card
            return card
        }
        gridView.update(cards: cards)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func windowDidResize(_ notification: Notification) {
        gridView.recalculateLayout()
    }

    func focusSearch() {
        makeFirstResponder(searchField)
    }

    deinit {
        if let observer = clipViewObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
