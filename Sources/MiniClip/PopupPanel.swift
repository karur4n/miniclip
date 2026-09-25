import AppKit

final class PopupPanel {
    private static let cornerRadius: CGFloat = 10

    private let panel: NSPanel
    private var monitors: [Any] = []

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(text: String, actions: [Action], at point: NSPoint) {
        close()

        let buttons = actions.map { action in
            MenuItemButton(title: action.title, symbol: action.symbol) { [weak self] in
                self?.close()
                action.perform(text)
            }
        }
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        // NOTE: 背後のウインドウをぼかす場合、layer の cornerRadius では形が切り抜かれない。maskImage で角を丸める
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        fill(background, with: stack)

        let border = BorderView(radius: Self.cornerRadius)
        fill(background, with: border)

        panel.contentView = background
        let size = stack.fittingSize
        panel.setFrame(frame(size: size, above: point), display: true)
        panel.invalidateShadow()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }

        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
                self?.close()
            },
        ].compactMap { $0 }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.orderOut(nil)
    }

    private func fill(_ container: NSView, with view: NSView) {
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func frame(size: NSSize, above point: NSPoint) -> NSRect {
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 12)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        return NSRect(origin: origin, size: size)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

private final class BorderView: NSView {
    init(radius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.borderWidth = 0.5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class MenuItemButton: NSView {
    private let icon: NSImageView
    private let label: NSTextField
    private let handler: () -> Void
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init(title: String, symbol: String, handler: @escaping () -> Void) {
        icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!)
        label = NSTextField(labelWithString: title)
        self.handler = handler
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5

        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        label.font = .systemFont(ofSize: 13)
        addSubview(icon)
        addSubview(label)
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        // NOTE: 自分のアプリは前面にいないので .activeAlways がないとカーソルの出入りを受け取れない
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = isHovered ? NSColor.controlAccentColor.cgColor : nil
        label.textColor = isHovered ? .white : .labelColor
        icon.contentTintColor = isHovered ? .white : .labelColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            handler()
        }
    }
}
