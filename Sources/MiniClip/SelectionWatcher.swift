import AppKit

final class SelectionWatcher {
    private let onSelect: (NSPoint) -> Void
    private var monitor: Any?
    private var downLocation: NSPoint = .zero

    init(onSelect: @escaping (NSPoint) -> Void) {
        self.onSelect = onSelect
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            downLocation = location
        case .leftMouseUp:
            let dragged = hypot(location.x - downLocation.x, location.y - downLocation.y) >= 5
            if dragged || event.clickCount >= 2 {
                onSelect(location)
            }
        default:
            break
        }
    }
}
