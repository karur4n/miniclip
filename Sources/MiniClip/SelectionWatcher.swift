import AppKit

final class SelectionWatcher {
    private let onSelect: (NSPoint) -> Void
    private var monitor: Any?
    private var downLocation: NSPoint = .zero
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var dragChangeCountAtDown = 0

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
            dragChangeCountAtDown = dragPasteboard.changeCount
        case .leftMouseUp:
            // NOTE: ファイルや文字をドラッグして落とす操作では、ドラッグ用クリップボードが書き換わる。文字の選択では書き換わらない
            let droppedSomething = dragPasteboard.changeCount != dragChangeCountAtDown
            let dragged = hypot(location.x - downLocation.x, location.y - downLocation.y) >= 5
            if (dragged && !droppedSomething) || event.clickCount >= 2 {
                onSelect(location)
            }
        default:
            break
        }
    }
}
